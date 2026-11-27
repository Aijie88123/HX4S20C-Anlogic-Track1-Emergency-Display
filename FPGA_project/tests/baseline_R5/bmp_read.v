module bmp_read #(
    parameter integer CLK_FREQ_HZ      = 100_000_000,
    parameter integer RELIABLE_MEDIA = 0,
    parameter integer NUMBERED_SIX = 0,
    // ------------------------------------------------------------------
    // 载图**停滞**超时（毫秒）
    //
    // 为什么必须有（2026-09-21 上板复现 + 仿真复现，见
    // doc/BILIN9_BOARD_FAIL_ANALYSIS.md）：
    //   ST_LOAD_HDR / ST_LOAD_WAIT / ST_LOAD_DATA 三个状态**只有一条出口** ——
    //   等 SD 侧给 sd_sec_read_end（或 write_req_ack）。板上一旦哪一次扇区读
    //   没有回来（控制器在 S_CMD17 里拿到坏响应会**原地重发**、永远不给
    //   read_end），bmp_read 就**永远**停在那里：
    //       ready = (state == ST_IDLE) 恒为 0
    //         -> sd_card_bmp 的"看门狗超时后重发同一张"那一支要求 bmp_ready，
    //            永远进不去
    //         -> 整个轮播**永久死锁**（板上现象：卡在某一�张图不动，state_code=4）
    //   看门狗本来是来消卡死的，结果它自己也被同一条链锁住了。
    //
    // 所以超时**必须**放在 bmp_read 内部：它是唯一能保证"总能回到 ST_IDLE"
    // 的地方。窗口取 500 ms —— 正常载图时字节是**连续**来的，最长的一次空隙
    // 就是一个扇区（512 字节 @2.3 MB/s ≈ 0.22 ms），500 ms 有三个数量级余量，
    // 不会误伤；而它比 sd_card_bmp 的 1000 ms 短，所以先由这里松绑，
    // 外层再按既有逻辑记故障码 + 重发。
    // 0 = 关掉（只为仿真做 A/B）。
    parameter integer STALL_TIMEOUT_MS = 500,
    // ★ 载图越界守卫：已读扇区数越过 load_sector_latched + file_sector_count
    //   就放弃这次载图、回 ST_IDLE（推导见下面 load_limit_r 那一段）。
    //
    //   它与 STALL_TIMEOUT_MS 是**两条互补的路**，缺一条留一个洞：
    //     STALL_TIMEOUT_MS  盖"东西不来了"（装死 / CMD17 不响应）
    //     本条              盖"read_end 照来、字节却不来了"
    //   后者两个时间型看门狗都看不见 —— 它们的"有进展"信号里 read_end 一直在跳。
    //   板上 state_code=4 恒久那一种就是它。已在 tb 的 EMPTY_SECTORS_AFTER_NSEC
    //   那一维复现，A/B 见 sim/run_iverilog.bat 第 18f/18g 项。
    //
    //   1 = 开（默认，正式 build 走这条）；0 = 关（**只为仿真做 A/B**，
    //   关掉才能让 18f 复现出修之前那个自锁）。
    parameter integer LOAD_OVERRUN_GUARD = 1,
    // ★ "载图快读完了"的判据 —— 供叠加层决定**什么时候开始淡出**。
    //
    //   为什么需要一个新信号：叠加层原来用「上一张图的载图帧数」去预测这一张的
    //   提交时刻（smart_terminal_overlay_pipelined.v 的 fade_out_start）。
    //   那在"每张都 640x480、都约 24 帧"的年代是对的 —— 但 C2-a 放开分辨率之后，
    //   同一张卡上载图时长差 3 倍（640x480≈24 帧 / 800x600≈37 / **1280x720≈72**）。
    //   用上一张预测这一张，两个方向都会坏：
    //     图变大 → 淡出起得太早 → 提前全黑，白等几十帧（"黑屏时间变长"）
    //     图变小 → 淡出还没开始就提交了 → 亮着硬切（"转场断"）
    //
    //   而**淡出本身是固定 12 帧**，所以正确的触发点是"**离结束还差约 12 帧的字节数**"
    //   —— 一个**固定扇区数**，与图的大小无关，而且正好等于淡出的时长：
    //       12 帧 x (2.3 MB/s / 60 fps) = 12 x 38,333 B ≈ 460,000 B ≈ 900 扇区
    //   取 900：640x480（1801 扇区）在过半时触发、淡完正好提交；
    //           1280x720（5401 扇区）在 87% 处触发、同样淡完正好提交。
    //   ⇒ 黑屏窗口在**任何分辨率下都约等于 12 帧**，不再是"看上一张抽签"。
    //
    //   ⚠️ 取固定扇区数而不是"读完 87.5%"：比例对**大图**是对的，对**小图**会
    //      让淡出窗口短于 12 帧（640x480 的 12.5% 只有 3 帧），照样硬切。
    //      淡出时长是固定的，所以触发余量也必须是固定的。
    parameter integer NEARLY_DONE_SECTORS = 900
)(
    input                       clk,
    input                       rst,
    output                      ready,
    // ★ 本次载图已读到 file_sector_count - NEARLY_DONE_SECTORS 之后的扇区
    //   ⇒ "离读完还差约 12 帧"。供叠加层决定**何时开始淡出**（推导见上面的
    //   parameter）。纯组合输出，在 sd_card_clk 域；消费方要自己同步过去。
    output                      load_nearly_done,

    // 上电扫描：从 scan_start_sector 开始，顺序寻找前 scan_target_count 张 BMP
    input                       scan_start,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    input  [2:0]                scan_target_count,
    output reg                  scan_done,
    output reg [3:0]            scan_error_code,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [2:0]            scan_found_total,
    output reg [2:0]            scan_found_slot,

    // 按指定扇区加载一张图到 SDRAM
    input                       load_start,
    input                       load_abort,
    output reg                  load_complete,
    output wire [31:0]          load_debug,
    input  [31:0]               load_sector,

    input                       sd_init_done,
    output reg [3:0]            state_code,
    // ⚠️ bmp_width / bmp_height 这两个输入**从 C2-a 起不再参与匹配**。
    //    原来 header_match 要求"宽高必须严格等于它们"，那是固定 640x480 时代的产物。
    //    端口保留是为了不动 sd_card_bmp / 仿真替身的接口。
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,

    // 已解析出来的源图宽高 —— 送给写侧缩放器（bmp_write_scaler）
    output wire [15:0]          src_w,
    output wire [15:0]          src_h,
    // 进入 ST_LOAD_DATA 那一拍拉高一次：缩放器用它复位行/列累加器。
    // 必须在**头解析完之后**才发，此时 width/height 才是有效的。
    // ⚠️ 名字不能叫 data_start —— 本文件里 `reg [31:0] data_start` 已经是
    //    **FAT32 数据区起始 LBA** 了。重名的话 iverilog 会报重复声明，
    //    但这类撞名一旦被掩盖（比如位宽不同的同名信号被合并），
    //    就会把 FAT32 的地址算错 —— 属于最难查的一类。
    output reg                  pixel_start,

    output reg                  write_req,
    input                       write_req_ack,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    output reg                  bmp_data_wr_en,
    output reg [23:0]           bmp_data
);

localparam ST_IDLE      = 4'd0;
localparam ST_SCAN      = 4'd1;
localparam ST_LOAD_HDR  = 4'd2;
localparam ST_LOAD_WAIT = 4'd3;
localparam ST_LOAD_DATA = 4'd4;
// 上电定位：先走 FAT32 根目录（O(1)），失败才退化成逐扇区扫描（ST_SCAN）
localparam ST_FAT_MBR   = 4'd5;
localparam ST_FAT_PICK  = 4'd9;   // 按 part_sel 取 LBA（单独一拍，压组合链）
localparam ST_FAT_BPB   = 4'd6;
localparam ST_FAT_MUL   = 4'd7;   // 含 4 个相位，见 fat_phase
localparam ST_FAT_READ  = 4'd8;
localparam ST_BMP_CHK   = 4'd10;  // 读候选文件的第一个扇区，验 'BM' 魔数
localparam ST_DRAIN     = 4'd11;

// 四张 BMP 的固定文件尺寸（640x480x24 未压缩）
parameter [31:0] BMP_FILE_SIZE = 32'd921654;
// 根目录最多读多少个扇区（一个 cluster 的上限，防止病态卡把上电时间拖长）
parameter [7:0]  ROOT_SEC_MAX  = 8'd128;

localparam ST_CHAIN_PREP=5'd12,ST_CHAIN_READ=5'd13,ST_CHAIN_CHECK=5'd14,
           ST_CHAIN_SEEK=5'd15,ST_CHAIN_WAIT=5'd16;
reg [4:0] state;
reg [(NUMBERED_SIX?6:5)-1:0] named_seen;
reg [2:0] name_slot;reg name_good;
reg [3:0] fat_shift_left,root_shift_left;
reg [2:0] fat_slot,fat_hit_slot,chk_slot;
reg [27:0] fat_hit_cluster,chk_cluster,walk_cluster,slow_cluster,query_cluster,chain_next,pending_next;
reg [31:0] chk_size;
reg chain_file,chain_header,slow_query,slow_phase,chain_start;
reg [7:0] cluster_sector;
reg [15:0] directory_sectors;
// A single remaining-sector counter serves both overrun and fade thresholds.
// ceil(UINT32_MAX/512) fits in 24 bits; physical card addresses stay 32-bit.
reg [23:0] sectors_remaining;
reg [31:0] dib_size;
reg [15:0] planes;
reg [13:0] safe_stride;
reg [25:0] pixel_bytes;
reg [32:0] required_end,header_end;
wire hold_pixel_state=RELIABLE_MEDIA && chain_file && state>=ST_CHAIN_PREP;
wire [2:0] named_slot;
wire named_match,chain_valid,header_safe;
reg [9:0]  rd_cnt;

reg [7:0]  header_0;
reg [7:0]  header_1;
reg [31:0] file_len;
reg [31:0] pixel_offset;
reg [31:0] width;
reg [31:0] height;
reg [15:0] bit_count;
reg [31:0] compression;
reg        header_ok_r;

reg [31:0] scan_sector;
reg [31:0] load_sector_latched;
reg [31:0] bmp_len_cnt;

// ---- C2-a：BMP 行填充（stride）与行计数 ----
// BMP 规定**每行按 4 字节对齐**：stride = ceil(W*3/4)*4，行末补 0。
// 以前的工程完全不处理 stride —— 因为 640x480 时 640*3 = 1920 正好整除 4，
// **从来没暴露过这个问题**（320*3=960 / 800*3=2400 / 1280*3=3840 也都整除）。
// 只有 427x240（stride 1284 vs 1281）、213x120（+1 字节）这种宽度才测得出来。
// 不处理的话，宽度非 4 对齐的图会**每行斜切/彩边**。
// ⚠️ **必须打拍，两级**（这条是时序门拦下来的，不是风格问题）：
//    第一版写成纯组合
//        wire [13:0] w3     = width * 3;
//        wire [13:0] stride = (w3 + 3) & ~3;
//    于是 `width`（reg，一张图只锁存一次）一路组合穿过
//        MULT18 -> 加法 -> 加法 -> 比较(row_byte == stride-1) -> row_cnt[*].ce / data_done
//    实测 sd_card_clk 域 **25 条违例、最差 -1.716 ns**（Fmax 掉到 85.3 MHz），
//    且 25 条的起点全是同一个寄存器、终点全是 row_cnt/row_byte/data_done ——
//    整片违例就是这一个锥。数据路径 11.436 ns > 10 ns 预算，逻辑级数 8。
//    `width` 在装载期间根本不会变，所以这里没有任何"来不及算"的道理，
//    纯粹是当初没打拍。分两级是为了每级都真的宽松（而不是刚好压进去）：
//        第一级 width -> w3      ：只剩一个 MULT18    ≈ 4 ns
//        第二级 w3    -> stride-1：只剩两个加法      ≈ 2 ns
//    连 `-1` 也一起算掉，省得比较器前面再挂一个加法。
//
//    为什么不用加"有效"标志：这两级的结果**只在 ST_LOAD_DATA 里用**，
//    而进 ST_LOAD_DATA 之前至少要走完 ST_BMP_CHK 和 ST_LOAD_WAIT 的写握手，
//    远多于 2 拍；扫描阶段的垃圾值永远不会被读到。
wire [11:0] width12 = width[11:0];        // 高 16 位由 header_match 保证为 0

reg [13:0] w3_r;           // 第一级：W*3 <= 12285
reg [13:0] stride_m1_r;    // 第二级：stride - 1 = ceil(W*3/4)*4 - 1
always @(posedge clk or posedge rst) begin
    if (rst) begin
        w3_r        <= 14'd0;
        stride_m1_r <= 14'd0;
    end
    else begin
        // ⚠️ 写成**移位加法**，不要写 `width12 * 3` ——
        //    `*3` 会让 TD 起一个 MULT18，全设计 #dsp 从 23 变成 24，
        //    构建脚本的 DSP 门当场判失败（本工程的设计约定是缩放相关运算 0 DSP）。
        //    W*3 = W + (W<<1)，14 位够放（4095*3 = 12285 < 16384）。
        w3_r        <= {2'b0, width12} + {1'b0, width12, 1'b0};
        stride_m1_r <= ((w3_r + 14'd3) & 14'h3FFC) - 14'd1;
    end
end

reg  [13:0] row_byte;      // 本行已收字节 0..stride-1（含填充）
reg  [11:0] row_cnt;       // 已完成的源行数
reg         data_done;     // 像素数据收完（H 行齐了）
reg [1:0]  bmp_byte_idx;
// Counters belong to a frame, never to an individual FAT/data-sector state.
wire new_pixel_frame=(state==ST_LOAD_WAIT && write_req_ack);
wire reset_pixel_frame=new_pixel_frame || (state==ST_IDLE && (scan_start || load_start));
assign load_debug={row_cnt,bmp_len_cnt[19:0]};

// ------------------------------------------------------------------
// FAT32 定位（只读，不写盘）
//
// 目的：把「从 LBA 0 逐扇区扫到找到 4 张图」换成「读 MBR + BPB + 根目录」。
// 前者代价是 O(文件绝对 LBA)（实测 15 s），后者是常数（约 6 个扇区 ≈ 1.1 ms）。
//
// 关键时序约束：sd_card_clk 上已有一条 -0.633 ns 的既有违例
// （file_len -> scan_done，10 级逻辑）。所以这里**不能**引入乘法器或长组合链：
//   - cluster 偏移用桶形移位（SecPerClus 是 2 的幂）
//   - NumFATs * FATSz32 用顺序累加，不用 *
//   - cluster -> LBA 分两级寄存器流水
// ------------------------------------------------------------------
reg [31:0] part_lba_0, part_lba_1, part_lba_2, part_lba_3;
reg [7:0]  part_typ_0, part_typ_1, part_typ_2, part_typ_3;
reg [31:0] part_lba;                 // 选中的分区起始 LBA
reg mbr_fat_found,mbr_nonempty_found,mbr_capture;
reg [1:0]  part_sel;                 // 选中第几个分区项（打一拍，见 part_sel_c）

reg [7:0]  sec_per_clus;
reg [15:0] rsvd_sec_cnt;
reg [7:0]  num_fats;
reg [31:0] fat_sz32;
reg [31:0] root_clus;
reg [3:0]  clus_shift;               // log2(SecPerClus)
reg [3:0]  clus_shift_c;

reg [31:0] fat_area;                 // NumFATs * FATSz32（顺序累加）
reg [7:0]  fat_cnt;
reg [1:0]  fat_phase;
reg        fat_bpb_ok_r;
reg [31:0] base_lba;                 // part_lba + rsvd_sec_cnt
reg [31:0] root_sub;                 // RootClus - 2
reg [31:0] data_start;               // FAT32 数据区起始 LBA
reg [31:0] root_off;                 // (RootClus - 2) << clus_shift
reg [31:0] root_lba;                 // 根目录起始 LBA
reg [31:0] root_sector;              // 根目录扫描当前位置
reg [7:0]  root_sec_budget;          // 本轮读到 root_lba + budget 停
reg [3:0]  fat_found_cnt;            // FAT32 已找到几张
reg        fat_eod;                  // 目录项 0x00 => 目录结束

reg [7:0]  ent [0:31];               // 当前 32 字节目录项
reg        ent_valid_r;              // 一拍延迟：条目已收齐
reg [7:0]  ent_attr_r;

reg [31:0] fat_clus;
reg [31:0] fat_sub;
reg [3:0]  fat_pipe;
reg [31:0] fat_clus_off;
reg [31:0] fat_hit_lba;
reg        fat_hit;                  // 流水线输出的一拍命中脉冲
reg [3:0]  fat_ent_idx;              // 命中那一项的目录项序号（跟着流水线走）
reg [3:0]  fat_hit_idx;

reg [4:0]  fat_end_dly;              // 扇区结束的延时确认

// ---- 候选文件校验（'BM' 魔数）----
// 目录项只能证明「名字像 BMP 且尺寸对」，证明不了「文件内容真是 BMP」。
// 卡上很容易留下这种"僵尸"文件：tf_card/tools/sync_to_sd.py 同步新图前会把
// 旧 .bmp 的前两字节从 'BM' 改成 'XX' 来让老的暴力扫描跳过它们 ——
// 但**目录项一个字节都没改**（名字、扩展名、尺寸全都还是 921654）。
// 只看目录项就会把这些僵尸文件当成有效图，交给 ST_LOAD_HDR 后 header_match 失败，
// 停在 ST_IDLE 且 load_busy 永远不释放 —— 板上表现就是数码管恒为 1、黑屏。
// 所以必须和老的线性扫描一样，真去读第一个扇区确认 'BM'。
reg [31:0] chk_lba;                  // 待校验的候选 LBA
reg [31:0] resume_sector;            // 校验完回到根目录的哪个扇区
// 5 bit：命中第 15 项时 resume_entry = 16，表示"本扇区到此为止"，
// 用 4 bit 会回绕成 0 导致死循环
reg [4:0]  resume_entry;
reg        pend_chk;                 // 本扇区发现了候选，等这扇区读完再去验
reg [3:0]  ent_idx_r;                // 刚收齐的那一项在本扇区里的序号

wire [1:0]  part_sel_c;              // MBR 里选中第几个分区项
wire [31:0] lba_sel;                 // 对应的起始 LBA
wire       fat_sec_done;
wire       ent_ext_ok;
wire       ent_name_ok;
wire       ent_attr_ok;
wire       ent_size_ok;
wire       ent_match;wire ent_match_raw;reg ent_match_r;
wire       fat_bpb_ok;

// 选哪个分区项：优先 FAT32 类型，否则第一个非空项。
// 这一级只有 2 bit 输出，链路很短；把「选序号」和「按序号取 LBA」拆成两拍，
// 否则 8 路优先选择器 + 32 bit 选择会串成一条超过 10 ns 的组合链
// （实测过：会新引入 3 条 -0.25 ~ -0.46 ns 的违例）。
assign part_sel_c =
      ((part_typ_0 == 8'h0B) || (part_typ_0 == 8'h0C)) ? 2'd0
    : ((part_typ_1 == 8'h0B) || (part_typ_1 == 8'h0C)) ? 2'd1
    : ((part_typ_2 == 8'h0B) || (part_typ_2 == 8'h0C)) ? 2'd2
    : ((part_typ_3 == 8'h0B) || (part_typ_3 == 8'h0C)) ? 2'd3
    : (part_typ_0 != 8'h00) ? 2'd0
    : (part_typ_1 != 8'h00) ? 2'd1
    : (part_typ_2 != 8'h00) ? 2'd2
    : (part_typ_3 != 8'h00) ? 2'd3
    : 2'd0;                          // 没有 MBR：按 superfloppy 处理，LBA0 就是 BPB

assign lba_sel = RELIABLE_MEDIA ? part_lba_0 :
                 (part_sel == 2'd1) ? part_lba_1
               : (part_sel == 2'd2) ? part_lba_2
               : (part_sel == 2'd3) ? part_lba_3
               : part_lba_0;

assign fat_sec_done = (state == ST_FAT_READ) && (fat_end_dly == 5'd1);

// 目录项匹配：扩展名 BMP（不分大小写）+ 普通文件 + 尺寸等于目标 BMP 尺寸
assign ent_ext_ok  = RELIABLE_MEDIA ? (ent[8][0] && ent[9][0] && ent[10][0]) :
                     ((ent[8]  | 8'h20) == 8'h62) &&   // 'b'/'B'
                     ((ent[9]  | 8'h20) == 8'h6d) &&   // 'm'/'M'
                     ((ent[10] | 8'h20) == 8'h70);     // 'p'/'P'
assign ent_name_ok = (ent[0] != 8'h00) && (ent[0] != 8'hE5);   // 非结束、非已删除
assign ent_attr_ok = (ent_attr_r != 8'h0F) &&    // 非长文件名项
                     (ent_attr_r[4]  == 1'b0) && // 非目录
                     (ent_attr_r[3]  == 1'b0);   // 非卷标
// 目录项里的文件大小。⚠️ C2-a 起**不再要求严格等于 BMP_FILE_SIZE(921654)**：
// 那一条会把所有非 640x480 的图**静默跳过**（表现成"少几张图"）。
// 改成只要求"像个文件"（>= 54 字节，最小的 BMP 头）。
// 真正判别是不是 BMP 的是后面的 ST_BMP_CHK —— 它会**真的去读第一个扇区验证 'BM'**，
// 那一步天然免疫"僵尸文件"（目录项还在、内容已经不是 BMP 了）。
wire [31:0] ent_size = {ent[31], ent[30], ent[29], ent[28]};
assign ent_size_ok = (ent_size >= 32'd54);
// resume_entry：从 ST_BMP_CHK 回到根目录同一个扇区时，跳过已经处理过的那几项，
// 否则会把同一个候选反复挑出来，死循环。
assign ent_match=RELIABLE_MEDIA?ent_match_r:ent_match_raw;
always @(posedge clk or posedge rst)
 if(rst)ent_match_r<=0;else ent_match_r<=ent_match_raw;
assign ent_match_raw = ent_valid_r && ent_ext_ok && ent_name_ok &&
                     ent_attr_ok && ent_size_ok &&
                     ({1'b0, ent_idx_r} >= resume_entry) &&
                     (!RELIABLE_MEDIA || (named_match && !named_seen[named_slot] &&
                      {ent[21][3:0],ent[20],ent[27],ent[26]}>=28'd2));

// BPB 合理性检查：字段不合法就不指望 FAT32，直接退化成线性扫描
assign fat_bpb_ok  = (num_fats != 8'd0) && (fat_sz32 != 32'd0) &&
                     (sec_per_clus == 8'd1  || sec_per_clus == 8'd2  ||
                      sec_per_clus == 8'd4  || sec_per_clus == 8'd8  ||
                      sec_per_clus == 8'd16 || sec_per_clus == 8'd32 ||
                      sec_per_clus == 8'd64 || sec_per_clus == 8'd128);
// ---------------- 载图停滞超时（见模块头的说明） ----------------
localparam integer STALL_TICKS = (CLK_FREQ_HZ / 1000) * STALL_TIMEOUT_MS;
localparam [26:0]  STALL_LAST  = STALL_TICKS - 1;

reg  [26:0] stall_cnt;
// "有进展" = SD 侧还在给字节，或者扇区读还在收尾
wire sd_progress    = sd_sec_read_data_valid | sd_sec_read_end;
wire in_load_wait   = (state == ST_LOAD_HDR) ||
                      (state == ST_LOAD_WAIT) ||
                      (state == ST_LOAD_DATA) || hold_pixel_state;
wire in_scan_wait   = (state == ST_SCAN) ||
                      (state == ST_FAT_MBR) ||
                      (state == ST_FAT_BPB) ||
                      (state == ST_FAT_READ) ||
                      (state == ST_BMP_CHK) || (RELIABLE_MEDIA && !chain_file && state>=ST_CHAIN_PREP);
wire stall_armed    = (STALL_TIMEOUT_MS != 0) && (in_load_wait || in_scan_wait);

always @(posedge clk or posedge rst) begin
    if (rst) stall_cnt <= 27'd0;
    else if (!stall_armed || sd_progress) stall_cnt <= 27'd0;
    else if (stall_cnt != STALL_LAST)     stall_cnt <= stall_cnt + 27'd1;
end

wire stall_expire = stall_armed && (stall_cnt == STALL_LAST);

wire header_match;
wire bmp_data_valid;
reg [31:0] file_sector_count;
assign named_slot=name_slot;
assign named_match=name_good;
function [7:0] expected_name_char;
 input [2:0] pos,slot;
 begin case(pos)
  2:expected_name_char=slot==0?"a":slot==1?"e":"i";
  3:expected_name_char=slot==0?"l":slot==1?"v":"n";
  4:expected_name_char=slot==0?"a":slot==1?"a":"f";
  5:expected_name_char=slot==0?"r":slot==1?"c":"o";
  6:expected_name_char=slot==0?"m":" ";
  default:expected_name_char=" ";
 endcase end
endfunction
// Accumulate the 8.3 basename while it streams; no 64-bit filename register
// or wide equality comparator is needed in the production scanner.
always @(posedge clk or posedge rst)
 if(rst)begin name_slot<=7;name_good<=0;end
 else if(state==ST_FAT_READ && sd_sec_read_data_valid)begin
  if(rd_cnt[4:0]==0)name_good<=sd_sec_read_data=="0";
  else if(rd_cnt[4:0]==1)begin
   if(NUMBERED_SIX)begin
    case(sd_sec_read_data)"1":name_slot<=2;"2":name_slot<=3;"3":name_slot<=4;"4":name_slot<=5;"5":name_slot<=0;"6":name_slot<=1;default:name_slot<=7;endcase
    name_good<=name_good && sd_sec_read_data>="1" && sd_sec_read_data<="6";
   end else begin
    name_slot<=sd_sec_read_data[2:0];
    name_good<=name_good && sd_sec_read_data>="0" && sd_sec_read_data<="4";
   end
  end else if(rd_cnt[4:0]<8)
   name_good<=name_good && (NUMBERED_SIX?sd_sec_read_data==" ":(sd_sec_read_data|8'h20)==expected_name_char(rd_cnt[2:0],name_slot));
 end
assign chain_valid=chain_next>=2 && chain_next<28'hffffff0;
assign header_safe=!RELIABLE_MEDIA || (planes==1 && dib_size>=40 && !header_end[32] && pixel_offset>=header_end[31:0] && !required_end[32] && file_len>=required_end[31:0]);
// Registered metadata checks settle while the complete header sector arrives.
always @(posedge clk)begin
 safe_stride<=stride_m1_r+1'b1;
 pixel_bytes<=safe_stride*height[11:0];
 required_end<={1'b0,pixel_offset}+{7'd0,pixel_bytes};
 header_end<={1'b0,dib_size}+33'd14;
end
always @(posedge clk or posedge rst)
 if(rst)chain_next<=0;
 else if(state==ST_CHAIN_PREP)chain_next<=0;
 else if(state==ST_CHAIN_READ && sd_sec_read_data_valid && rd_cnt[8:2]==query_cluster[6:0])
  case(rd_cnt[1:0])
   0:chain_next[7:0]<=sd_sec_read_data;1:chain_next[15:8]<=sd_sec_read_data;
   2:chain_next[23:16]<=sd_sec_read_data;3:chain_next[27:24]<=sd_sec_read_data[3:0];
  endcase

wire [31:0] next_scan_sector_if_miss;

assign ready = (state == ST_IDLE);
// C2-a：接受**任意分辨率** 1..4095 x 1..4095（4095 覆盖 4K 的 3840），
// 仍然要求 24 位未压缩（缩放器的像素格式）；pixel_offset >= 54 顺带修掉
// "第 5 张图用了 BITMAPV5HEADER 多 84 字节被静默剔除"那个老坑。
// height 的高 16 位非 0（= 负高度 / top-down BMP）**仍然拒绝** —— 那会翻转图像方向，
// 而写通路的垂直翻转是按"自下而上"定的，两个叠一起会上下颠倒。
assign header_match = (header_0 == "B") &&
                      (header_1 == "M") &&
                      (width[31:16]  == 16'd0) && (width[15:0]  >= 16'd1) &&
                      (width[15:0]   <= 16'd4095) &&
                      (height[31:16] == 16'd0) && (height[15:0] >= 16'd1) &&
                      (height[15:0]  <= 16'd4095) &&
                      (bit_count    == 16'd24) &&
                      (compression  == 32'd0) &&
                      (pixel_offset >= 32'd54) &&
                      (file_len     >  pixel_offset) && header_safe;
// Register the header decision while the first sector is still streaming.
// The original combinational decision fed the scan/load address enables and
// became the worst sd_card_clk path.  Reading it only after the full header
// is available preserves behavior; the state machine consumes it at
// sd_sec_read_end, hundreds of cycles later.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_ok_r <= 1'b0;
    end else if (((state == ST_SCAN) || (state == ST_LOAD_HDR) ||
                  (state == ST_BMP_CHK)) && (rd_cnt >= 10'd34)) begin
        header_ok_r <= header_match;
    end else begin
        header_ok_r <= 1'b0;
    end
end

// 进入像素区了没有（bmp_len_cnt 从 ST_LOAD_DATA 开始逐字节计数）
wire in_pixels      = (bmp_len_cnt >= pixel_offset) && !data_done;
wire byte_in_pixels = (state==ST_LOAD_DATA) && (sd_sec_read_data_valid == 1'b1) && in_pixels;
// ⚠️ 只有**行内非填充**的字节才送去拼像素。填充字节照样要让 row_byte 走，
//    否则行边界会错位（这就是"斜切"的来源）。
assign bmp_data_valid = byte_in_pixels && (row_byte < w3_r);
assign src_w = width[15:0];
assign src_h = height[15:0];
// ceil(file_len / 512)。刻意不写 (file_len + 32'd511) >> 9：
// 那样 file_len 的最低位要一路进位到 bit9 以上，再串上 scan_sector 的
// 32 位加法，在 sd_card_clk（100 MHz / 10 ns）里综合出 6 级 ADDER，
// 实测 10.007 ns，差 -0.287 ns。而 scan_done 正是由这条链算出来的，
// 它一旦抖动，上层 "scan_done && bmp_ready && display_valid && !load_busy"
// 的切图条件就整体失效——表现就是轮播和 S2 手动切换都不响应。
// 等价写法：(A + 511) >> 9 == (A >> 9) + (A[8:0] != 0)
// 低 9 位只参与一个或归约，不再进进位链。
// One extra register separates sector rounding from load-limit and scan
// address arithmetic. Header bytes settle hundreds of clocks before use.
always @(posedge clk or posedge rst) begin
    if(rst) file_sector_count <= 32'd1;
    else file_sector_count <= (file_len == 32'd0) ? 32'd1 :
        ((file_len >> 9) + {31'd0, |file_len[8:0]});
end
assign next_scan_sector_if_miss  = scan_sector + 32'd1;

// ------------------------------------------------------------------
// ★ C2-a 载图终止判据之三：**已读扇区数越过 file_sector_count**。
//
//   为什么非有这一条不可 —— 另外两条判据测的都是"**还有没有东西在动**"：
//       bmp_read 的停滞超时      sd_sec_read_data_valid | sd_sec_read_end
//       sd_card_bmp 的看门狗      bmp_data_wr_en | write_en
//   而板上的失败恰恰是「**read_end 一直在来、字节却没了**」：
//   两个信号都还在跳 ⇒ 两个看门狗都**永远不到期** ⇒ state_code 恒 4、轮播停摆。
//   这一维已经能在 tb_multires_load_chain 里复现（EMPTY_SECTORS_AFTER_NSEC）。
//
//   这一条不看"动没动"，看的是**已经走了多远**：BMP 头声明这张图只有
//   ceil(bfSize/512) 个扇区，越过它就**不可能**再凑齐
//   pixel_offset + stride*H 个字节 —— 再往下读只是让地址一直往前走。
//
//   对一张健康的图它**永远不会触发**：最多读到第 file_sector_count 个扇区
//   （索引 0..file_sector_count-1），load_secs_done 最大 file_sector_count-1。
//
//   ⚠️ 它只保证"bmp_read 一定回得到 ST_IDLE"，**不保证卡本身是好的**：
//      卡真坏时重试仍会失败，但整条链不会自锁 —— ready 一直放得出来，
//      卡一恢复正常立刻就能出图。
//   ⚠️ 只在 ST_LOAD_DATA 用。进入该状态时 sd_sec_read_addr 已被
//      ST_LOAD_HDR 拨回 load_sector_latched，所以计数从 0 起。
//
//   ⚠️ 上界**必须打一拍**，理由与下面 next_match_sector_r 那段**逐字相同**：
//      load_sector_latched 与 file_sector_count 在一次载图里都是常量
//      （file_len 只在 ST_SCAN/ST_LOAD_HDR 被写，见 header 解析那一块），
//      所以 registered 版本语义完全等价，却把 32 位加法从关键路径上摘掉，
//      只剩一个 32 位比较 —— 比 file_len->scan_done 那条既有最差路径还短。
//      写成 `sd_sec_read_addr - load_sector_latched >= file_sector_count`
//      会白送一级 32 位减法进 sd_card_clk 的 10 ns 预算。
// ------------------------------------------------------------------
reg [31:0] load_limit_r;
always @(posedge clk or posedge rst) begin
    if (rst) load_limit_r <= 32'd0;
    else     load_limit_r <= load_sector_latched + file_sector_count;
end
wire load_overrun = (LOAD_OVERRUN_GUARD != 0) && (RELIABLE_MEDIA ? sectors_remaining<=1 : sd_sec_read_addr>=load_limit_r);

// ★ "快读完了"（供叠加层决定何时开始淡出，推导见 parameter NEARLY_DONE_SECTORS）。
//
// 同样**打一拍**：load_limit_r 在一次载图里是常量，减一个常数也是常量，
// 打拍语义完全等价，却把一级 32 位减法从 sd_card_clk 的 10 ns 预算里摘掉，
// 只剩一个比较（与 load_overrun 共用同一种形状）。
//
// 文件比 NEARLY_DONE_SECTORS 还短时**钳到起点**：那种图本来就不到 0.2 s、
// 装不下 12 帧的淡出，从载图一开始就淡是唯一不会硬切的选择。不钳的话
// 32 位减法会下溢成一个巨大的数，判据恒为真 —— 看起来一样，但是靠错误工作。
wire [31:0] load_soft_base = (file_sector_count > NEARLY_DONE_SECTORS)
                             ? (load_limit_r - NEARLY_DONE_SECTORS)
                             : load_sector_latched;
reg [31:0] load_soft_r;
always @(posedge clk or posedge rst) begin
    if (rst) load_soft_r <= 32'd0;
    else     load_soft_r <= load_soft_base;
end
// ★ 2026-09-29：把"快读完了"限定在**真正在载数据**的状态里。
//   不加这一条时，空闲时 sd_sec_read_addr 还停在上一张的末尾，比较结果一直是 1，
//   叠加层会在下一张**刚开始载**就进淡出窗口 —— 上板现象就是"每次切图都先黑一下"。
//   （这一条是 2026-09-27 交付里验证过的显示侧修正，不碰扫描/载图判据。）
assign load_nearly_done = (state == ST_LOAD_DATA) &&
                          (RELIABLE_MEDIA ? sectors_remaining<=NEARLY_DONE_SECTORS : sd_sec_read_addr>=load_soft_r);

// ------------------------------------------------------------------
// scan_sector + file_sector_count 打一拍再用。
//
// 这条链是 file_len -> file_sector_count -> +scan_sector -> 和 scan_max_sector
// 比较 -> state/scan_done，实测 10 级逻辑（ADDER=5 + 比较器），在 sd_card_clk
// （10 ns）上是全设计最差的一条：
//   fat32 版 -0.144 ns，本版 5 图版 -0.257 ns（布局布线抖动）
//
// 但 scan_sector 只在每次 sd_sec_read_end 才变，file_len 只在该扇区的前 6 个
// 字节解析时写入 —— 两者在一次扇区读取（上万个周期）里**都是常量**。所以把
// 加法结果打一拍再用，语义完全等价，组合链被切成两段。
//
// 这不是"顺手优化"：file_len 在**每一次图片加载的头扇区读完后都会重写**
// （ST_LOAD_HDR），也就是说这条违例路径在每次切图时都会真实翻转一次。
// ------------------------------------------------------------------
reg [31:0] next_match_sector_r;
always @(posedge clk or posedge rst) begin
    if (rst)
        next_match_sector_r <= 32'd0;
    else
        next_match_sector_r <= scan_sector + file_sector_count;
end

// A successful sector transaction must deliver exactly 512 data bytes.
// Empty and truncated sectors both enter the upper-FSM recovery path.
reg [9:0] sector_byte_count;
reg sector_in_flight;
// Maintain the exact count==512 condition with the byte counter. Its single
// register drives recovery; the ten-bit decode no longer fans into all FSM muxes.
reg sector_complete;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        sector_byte_count <= 10'd0;
        sector_in_flight <= 1'b0;
        sector_complete <= 1'b0;
    end else begin
        if (!sd_init_done || sd_sec_read_end)
            sector_in_flight <= 1'b0;
        else if (sd_sec_read)
            sector_in_flight <= 1'b1;
        // Requests may be lowered as soon as a FAT candidate is found, while
        // the transport is still streaming that sector. Count the entire
        // transaction and clear only at its completion, not at request release.
        if (!sd_init_done || sd_sec_read_end) begin
            sector_byte_count <= 10'd0;
            sector_complete <= 1'b0;
        end else if (sd_sec_read_data_valid) begin
            sector_byte_count <= sector_byte_count + 10'd1;
            sector_complete <= (sector_byte_count == 10'd511);
        end
    end
end

wire read_fail = sd_sec_read_end && !sector_complete &&
                 (in_scan_wait || in_load_wait);
// Preserve a stage-specific diagnosis until a new scan starts. A complete
// network packet does not prove that its source was a complete card sector.
always @(posedge clk or posedge rst)begin
 if(rst)scan_error_code<=0;
 else if(scan_start && state==ST_IDLE)scan_error_code<=0;
 else if(read_fail)scan_error_code<=9;
 else if(stall_expire)scan_error_code<=3;
 else if(state==ST_FAT_MUL && !fat_bpb_ok_r && scan_error_code!=9)scan_error_code<=6;
 else if((state==ST_BMP_CHK || state==ST_LOAD_HDR) && sd_sec_read_end && !header_ok_r && scan_error_code!=9)scan_error_code<=8;
 else if(state==ST_CHAIN_CHECK && chain_file && !chain_valid)scan_error_code<=10;
 else if(state==ST_CHAIN_CHECK && chain_file && (slow_query ? chain_next==pending_next : chain_next==slow_cluster))scan_error_code<=11;
 else if(state==ST_LOAD_DATA && sd_sec_read_end && load_overrun && !data_done)scan_error_code<=12;
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_cnt <= 10'd0;
    end else if ((state == ST_SCAN) || (state == ST_LOAD_HDR) ||
                 (state == ST_FAT_MBR) || (state == ST_FAT_BPB) ||
                 (state == ST_FAT_READ) || (state == ST_BMP_CHK) || (RELIABLE_MEDIA && state==ST_CHAIN_READ)) begin
        if (sd_sec_read_data_valid)
            rd_cnt <= rd_cnt + 10'd1;
        else if (sd_sec_read_end)
            rd_cnt <= 10'd0;
    end else begin
        rd_cnt <= 10'd0;
    end
end

// ---------------- MBR 分区表捕获（LBA 0） ----------------
// 分区项 i 在偏移 446 + 16*i；+4 是类型，+8..+11 是小端起始 LBA
generate if(!RELIABLE_MEDIA)begin: legacy_mbr
always @(posedge clk or posedge rst) begin
    if (rst) begin
        part_lba_0 <= 32'd0; part_lba_1 <= 32'd0;
        part_lba_2 <= 32'd0; part_lba_3 <= 32'd0;
        part_typ_0  <= 8'd0; part_typ_1  <= 8'd0;
        part_typ_2  <= 8'd0; part_typ_3  <= 8'd0;
    end else if ((state == ST_FAT_MBR) && sd_sec_read_data_valid) begin
        case (rd_cnt)
            10'd450: part_typ_0 <= sd_sec_read_data;
            10'd454: part_lba_0[7:0]   <= sd_sec_read_data;
            10'd455: part_lba_0[15:8]  <= sd_sec_read_data;
            10'd456: part_lba_0[23:16] <= sd_sec_read_data;
            10'd457: part_lba_0[31:24] <= sd_sec_read_data;
            10'd466: part_typ_1 <= sd_sec_read_data;
            10'd470: part_lba_1[7:0]   <= sd_sec_read_data;
            10'd471: part_lba_1[15:8]  <= sd_sec_read_data;
            10'd472: part_lba_1[23:16] <= sd_sec_read_data;
            10'd473: part_lba_1[31:24] <= sd_sec_read_data;
            10'd482: part_typ_2 <= sd_sec_read_data;
            10'd486: part_lba_2[7:0]   <= sd_sec_read_data;
            10'd487: part_lba_2[15:8]  <= sd_sec_read_data;
            10'd488: part_lba_2[23:16] <= sd_sec_read_data;
            10'd489: part_lba_2[31:24] <= sd_sec_read_data;
            10'd498: part_typ_3 <= sd_sec_read_data;
            10'd502: part_lba_3[7:0]   <= sd_sec_read_data;
            10'd503: part_lba_3[15:8]  <= sd_sec_read_data;
            10'd504: part_lba_3[23:16] <= sd_sec_read_data;
            10'd505: part_lba_3[31:24] <= sd_sec_read_data;
            default: ;
        endcase
    end
end

end else begin: streaming_mbr
// A single selected LBA starts as the first nonempty partition, and is
// overwritten by the first FAT32 partition only. Later entries cannot replace
// it. This preserves the legacy priority without two retained address banks.
always @(posedge clk or posedge rst)begin
 if(rst)begin
  part_lba_0<=0;mbr_fat_found<=0;mbr_nonempty_found<=0;mbr_capture<=0;
 end else if(state==ST_IDLE && scan_start)begin
  part_lba_0<=0;mbr_fat_found<=0;mbr_nonempty_found<=0;mbr_capture<=0;
 end else if(state==ST_FAT_MBR && sd_sec_read_data_valid && rd_cnt>=446 && rd_cnt<510)begin
  if(rd_cnt[3:0]==2)begin
   mbr_capture<=!mbr_fat_found && ((sd_sec_read_data==8'h0b || sd_sec_read_data==8'h0c) || (!mbr_nonempty_found && sd_sec_read_data!=0));
   if(sd_sec_read_data==8'h0b || sd_sec_read_data==8'h0c)mbr_fat_found<=1;
   if(sd_sec_read_data!=0)mbr_nonempty_found<=1;
  end
  if(mbr_capture)case(rd_cnt[3:0])
   6:part_lba_0[7:0]<=sd_sec_read_data;
   7:part_lba_0[15:8]<=sd_sec_read_data;
   8:part_lba_0[23:16]<=sd_sec_read_data;
   9:part_lba_0[31:24]<=sd_sec_read_data;
  endcase
 end
end
end endgenerate

// ---------------- FAT32 BPB 字段捕获（分区起始扇区） ----------------
always @(posedge clk or posedge rst) begin
    if (rst) begin
        sec_per_clus <= 8'd0;
        rsvd_sec_cnt <= 16'd0;
        num_fats     <= 8'd0;
        fat_sz32     <= 32'd0;
        root_clus    <= 32'd0;
    end else if ((state == ST_FAT_BPB) && sd_sec_read_data_valid) begin
        case (rd_cnt)
            10'd13: sec_per_clus      <= sd_sec_read_data;
            10'd14: rsvd_sec_cnt[7:0] <= sd_sec_read_data;
            10'd15: rsvd_sec_cnt[15:8]<= sd_sec_read_data;
            10'd16: num_fats          <= sd_sec_read_data;
            10'd36: fat_sz32[7:0]     <= sd_sec_read_data;
            10'd37: fat_sz32[15:8]    <= sd_sec_read_data;
            10'd38: fat_sz32[23:16]   <= sd_sec_read_data;
            10'd39: fat_sz32[31:24]   <= sd_sec_read_data;
            10'd44: root_clus[7:0]    <= sd_sec_read_data;
            10'd45: root_clus[15:8]   <= sd_sec_read_data;
            10'd46: root_clus[23:16]  <= sd_sec_read_data;
            10'd47: root_clus[31:24]  <= sd_sec_read_data;
            default: ;
        endcase
    end
end

// SecPerClus 恒为 2 的幂，取 log2 给桶形移位用（全程不用乘法器）
always @(*) begin
    case (sec_per_clus)
        8'd1:    clus_shift_c = 4'd0;
        8'd2:    clus_shift_c = 4'd1;
        8'd4:    clus_shift_c = 4'd2;
        8'd8:    clus_shift_c = 4'd3;
        8'd16:   clus_shift_c = 4'd4;
        8'd32:   clus_shift_c = 4'd5;
        8'd64:   clus_shift_c = 4'd6;
        8'd128:  clus_shift_c = 4'd7;
        default: clus_shift_c = 4'd0;
    endcase
end

// ---------------- 根目录 32 字节目录项缓存 ----------------
// 整项缓存进寄存器后再做匹配，避免把 SPI 数据输入接进长组合链
always @(posedge clk or posedge rst) begin
    if (rst) begin
        ent_valid_r <= 1'b0;
        ent_attr_r  <= 8'd0;
        ent_idx_r   <= 4'd0;
    end else if ((state == ST_FAT_READ) && sd_sec_read_data_valid) begin
        if(RELIABLE_MEDIA && rd_cnt[4:0]==8)
            ent[8]<={7'd0,(sd_sec_read_data|8'h20)=="b"};
        else if(RELIABLE_MEDIA && rd_cnt[4:0]==9)
            ent[9]<={7'd0,(sd_sec_read_data|8'h20)=="m"};
        else if(RELIABLE_MEDIA && rd_cnt[4:0]==10)
            ent[10]<={7'd0,(sd_sec_read_data|8'h20)=="p"};
        else ent[rd_cnt[4:0]]<=sd_sec_read_data;
        ent_valid_r      <= (rd_cnt[4:0] == 5'd31);
        if (rd_cnt[4:0] == 5'd31)
            ent_idx_r <= rd_cnt[8:5];
        if (rd_cnt[4:0] == 5'd11)
            ent_attr_r <= sd_sec_read_data;
    end else begin
        ent_valid_r <= 1'b0;
    end
end

// ---- 校验候选文件：只取每个扇区最前面两个字节 ----
// chk_0 / chk_1 / chk_seen 只在这一个 always 块里驱动。
// 别为了"清残留"在主状态机里再赋一次 chk_0 —— 那会变成多驱动，
// TD 直接报 HDL-8007 把整个 bmp_read 降级成 black box（实测踩过两次）。
// 用 chk_seen 表示"本扇区确实收到了前两个字节"，同样能挡住上一次的残留值。
// 目录项首字节 0x00 => 目录到此结束，不用再往后读
always @(posedge clk or posedge rst) begin
    if (rst) fat_eod <= 1'b0;
    else if (state != ST_FAT_READ) fat_eod <= 1'b0;
    else if (ent_valid_r && (ent[0] == 8'h00)) fat_eod <= 1'b1;
end

// Production shifts one bit per clock for at most seven clocks. This shares
// the existing address registers and removes wide barrel shifters.
// cluster -> LBA 的 4 级寄存器流水（每级只做一次加减/移位，保证 10 ns 收得住）
// 连续两次命中的间隔至少是 32 字节 ≈ 1152 周期，而流水线只有 4 级，
// 所以这里不需要排队：上一次命中必然已经发完。
always @(posedge clk or posedge rst) begin
    if (rst) begin
        fat_clus     <= 32'd0;
        fat_sub      <= 32'd0;
        fat_pipe     <= 4'd0;fat_shift_left<=0;
        fat_clus_off <= 32'd0;
        fat_hit_lba  <= 32'd0;
        fat_hit      <= 1'b0;
        fat_ent_idx  <= 4'd0;
        fat_hit_idx  <= 4'd0;fat_slot<=0;fat_hit_slot<=0;fat_hit_cluster<=0;
    end else begin
        fat_hit <= 1'b0;

        if (fat_pipe == 4'd0) begin
            if(RELIABLE_MEDIA && chain_start)begin
                fat_clus<={4'd0,walk_cluster};fat_pipe<=1;
            end else if (ent_match) begin
                fat_slot<=named_slot;
                fat_clus    <= {ent[21], ent[20], ent[27], ent[26]};
                fat_ent_idx <= ent_idx_r;
                fat_pipe    <= 4'd1;
            end
        end else begin
            case (fat_pipe)
                4'd1: begin
                    fat_sub  <= fat_clus - 32'd2;fat_shift_left<=clus_shift;
                    fat_pipe <= 4'd2;
                end
                4'd2: begin
                    if(RELIABLE_MEDIA && fat_shift_left!=0)begin
                        fat_sub<=fat_sub<<1;fat_shift_left<=fat_shift_left-1'b1;
                    end else begin
                        fat_clus_off<=RELIABLE_MEDIA?fat_sub:(fat_sub<<clus_shift);
                        fat_pipe<=3;
                    end
                end
                4'd3: begin
                    fat_hit_lba <= data_start + fat_clus_off;
                    fat_pipe    <= 4'd4;
                end
                4'd4: begin
                    fat_hit     <= 1'b1;
                    fat_hit_idx <= fat_ent_idx;fat_hit_slot<=fat_slot;fat_hit_cluster<=fat_clus[27:0];
                    fat_pipe    <= 4'd0;
                end
                default: fat_pipe <= 4'd0;
            endcase
        end
    end
end

// 本扇区最后一个目录项（第 15 项）的命中要在 sd_sec_read_end 之后几拍才出来，
// 所以把「扇区结束」延时 16 拍再确认，避免漏掉最后一项。
always @(posedge clk or posedge rst) begin
    if (rst) fat_end_dly <= 5'd0;
    else if (state != ST_FAT_READ) fat_end_dly <= 5'd0;
    else if (sd_sec_read_end) fat_end_dly <= 5'd16;
    else if (fat_end_dly != 5'd0) fat_end_dly <= fat_end_dly - 5'd1;
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_0     <= 8'd0;
        header_1     <= 8'd0;
        file_len     <= 32'd0;
        pixel_offset <= 32'd54;
        width        <= 32'd0;
        height       <= 32'd0;
        bit_count    <= 16'd0;
        compression  <= 32'd0;dib_size<=0;planes<=0;
    end else if (((state == ST_SCAN) || (state == ST_LOAD_HDR) ||
                  (state == ST_BMP_CHK)) && sd_sec_read_data_valid) begin
        case (rd_cnt)
            10'd0 : header_0 <= RELIABLE_MEDIA ? (sd_sec_read_data=="B"?"B":8'd0) : sd_sec_read_data;
            10'd1 : header_1 <= RELIABLE_MEDIA ? (sd_sec_read_data=="M"?"M":8'd0) : sd_sec_read_data;

            10'd14:dib_size[7:0]<=sd_sec_read_data;10'd15:dib_size[15:8]<=sd_sec_read_data;
            10'd16:dib_size[23:16]<=sd_sec_read_data;10'd17:dib_size[31:24]<=sd_sec_read_data;
            10'd26:planes[7:0]<=RELIABLE_MEDIA ? {7'd0,sd_sec_read_data==1} : sd_sec_read_data;10'd27:planes[15:8]<=RELIABLE_MEDIA ? {7'd0,|sd_sec_read_data} : sd_sec_read_data;
            10'd2 : file_len[7:0] <= sd_sec_read_data;
            10'd3 : file_len[15:8] <= sd_sec_read_data;
            10'd4 : file_len[23:16] <= sd_sec_read_data;
            10'd5 : file_len[31:24] <= sd_sec_read_data;

            10'd10: pixel_offset[7:0] <= sd_sec_read_data;
            10'd11: pixel_offset[15:8] <= sd_sec_read_data;
            10'd12: pixel_offset[23:16] <= sd_sec_read_data;
            10'd13: pixel_offset[31:24] <= sd_sec_read_data;

            10'd18: width[7:0] <= sd_sec_read_data;
            10'd19: width[15:8] <= RELIABLE_MEDIA ? {3'd0,|sd_sec_read_data[7:4],sd_sec_read_data[3:0]} : sd_sec_read_data;
            10'd20: width[23:16] <= RELIABLE_MEDIA ? {7'd0,|sd_sec_read_data} : sd_sec_read_data;
            10'd21: width[31:24] <= RELIABLE_MEDIA ? {7'd0,|sd_sec_read_data} : sd_sec_read_data;

            10'd22: height[7:0] <= sd_sec_read_data;
            10'd23: height[15:8] <= RELIABLE_MEDIA ? {3'd0,|sd_sec_read_data[7:4],sd_sec_read_data[3:0]} : sd_sec_read_data;
            10'd24: height[23:16] <= RELIABLE_MEDIA ? {7'd0,|sd_sec_read_data} : sd_sec_read_data;
            10'd25: height[31:24] <= RELIABLE_MEDIA ? {7'd0,|sd_sec_read_data} : sd_sec_read_data;

            10'd28: bit_count[7:0] <= RELIABLE_MEDIA ? (sd_sec_read_data==24?8'd24:8'd0) : sd_sec_read_data;
            10'd29: bit_count[15:8] <= RELIABLE_MEDIA ? {7'd0,|sd_sec_read_data} : sd_sec_read_data;

            10'd30: compression[7:0] <= RELIABLE_MEDIA ? {7'd0,|sd_sec_read_data} : sd_sec_read_data;
            10'd31: compression[15:8] <= RELIABLE_MEDIA ? {7'd0,|sd_sec_read_data} : sd_sec_read_data;
            10'd32: compression[23:16] <= RELIABLE_MEDIA ? {7'd0,|sd_sec_read_data} : sd_sec_read_data;
            10'd33: compression[31:24] <= RELIABLE_MEDIA ? {7'd0,|sd_sec_read_data} : sd_sec_read_data;
            default: ;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_len_cnt <= 32'd0;
    end else if (reset_pixel_frame) begin
        bmp_len_cnt <= 32'd0;
    end else if (state == ST_LOAD_DATA && sd_sec_read_data_valid) begin
        bmp_len_cnt <= bmp_len_cnt + 32'd1;
    end
end

// C2-a：行/列计数。收满 H 行就 data_done —— **不再用 file_len 作终止条件**，
// 因为不同分辨率的 file_len 千差万别，而"W x H 个像素"才是真正的判据。
always @(posedge clk or posedge rst) begin
    if (rst) begin
        row_byte  <= 14'd0;
        row_cnt   <= 12'd0;
        data_done <= 1'b0;
    end else if (reset_pixel_frame) begin
        row_byte  <= 14'd0;
        row_cnt   <= 12'd0;
        data_done <= 1'b0;
    end else if (byte_in_pixels) begin
        if (row_byte == stride_m1_r) begin
            row_byte <= 14'd0;
            if (row_cnt == (height[11:0] - 12'd1))
                data_done <= 1'b1;
            else
                row_cnt <= row_cnt + 12'd1;
        end else begin
            row_byte <= row_byte + 14'd1;
        end
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_byte_idx <= 2'd0;
    end else if (reset_pixel_frame) begin
        bmp_byte_idx <= 2'd0;
    end else if (state == ST_LOAD_DATA && bmp_data_valid) begin
        bmp_byte_idx <= (bmp_byte_idx == 2'd2) ? 2'd0 : (bmp_byte_idx + 2'd1);
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_data_wr_en <= 1'b0;
        bmp_data       <= 24'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid) begin
            case (bmp_byte_idx)
                2'd0: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[7:0]  <= sd_sec_read_data;
                end
                2'd1: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[15:8] <= sd_sec_read_data;
                end
                2'd2: begin
                    bmp_data_wr_en  <= 1'b1;
                    bmp_data[23:16] <= sd_sec_read_data;
                end
                default: begin
                    bmp_data_wr_en <= 1'b0;
                end
            endcase
        end else begin
            bmp_data_wr_en <= 1'b0;
        end
    end else begin
        bmp_data_wr_en <= 1'b0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        load_complete     <= 1'b0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        // 注意：fat_pipe 只在 FAT32 流水线那个 always 块里驱动，
        // 这里绝对不能再赋值，否则综合报 HDL-8007 多驱动错误。
        fat_found_cnt     <= 4'd0;
        fat_bpb_ok_r      <= 1'b0;
        pend_chk          <= 1'b0;
        named_seen<=0;scan_found_slot<=0;chk_slot<=0;chk_cluster<=0;chk_size<=0;
        walk_cluster<=0;slow_cluster<=0;query_cluster<=0;pending_next<=0;
        chain_file<=0;chain_header<=0;slow_query<=0;slow_phase<=0;chain_start<=0;
        cluster_sector<=0;directory_sectors<=0;sectors_remaining<=0;root_shift_left<=0;
    end else if (!sd_init_done) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        load_complete     <= 1'b0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        // 注意：fat_pipe 只在 FAT32 流水线那个 always 块里驱动，
        // 这里绝对不能再赋值，否则综合报 HDL-8007 多驱动错误。
        fat_found_cnt     <= 4'd0;
        fat_bpb_ok_r      <= 1'b0;
        pend_chk          <= 1'b0;
        named_seen<=0;scan_found_slot<=0;chk_slot<=0;chk_cluster<=0;chk_size<=0;
        walk_cluster<=0;slow_cluster<=0;query_cluster<=0;pending_next<=0;
        chain_file<=0;chain_header<=0;slow_query<=0;slow_phase<=0;chain_start<=0;
        cluster_sector<=0;directory_sectors<=0;sectors_remaining<=0;root_shift_left<=0;
    end else begin
        load_complete <= 1'b0;
        scan_found_valid <= 1'b0;
        chain_start<=0;
        pixel_start      <= 1'b0;   // 默认清；下面进 ST_LOAD_DATA 时置一拍

        case (state)
            ST_IDLE: begin
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;

                if (scan_start) begin
                    scan_done        <= 1'b0;named_seen<=0;chain_file<=0;directory_sectors<=0;
                    scan_found_total <= 3'd0;
                    fat_found_cnt    <= 4'd0;
                    scan_sector      <= scan_start_sector;
                    sd_sec_read_addr <= 32'd0;      // 先读 MBR
                    state            <= ST_FAT_MBR; // 走 FAT32，不再逐扇区扫
                end else if (load_start) begin
                    load_sector_latched <= load_sector;
                    sd_sec_read_addr    <= load_sector;
                    if(RELIABLE_MEDIA)begin
                        walk_cluster<=load_sector[27:0];slow_cluster<=load_sector[27:0];
                        chain_file<=1;chain_header<=1;slow_phase<=0;cluster_sector<=0;sectors_remaining<=0;
                        state<=ST_CHAIN_SEEK;
                    end else state<=ST_LOAD_HDR;
                end
            end

            ST_SCAN: if(!RELIABLE_MEDIA)begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;

                    if (header_ok_r && !read_fail && (!RELIABLE_MEDIA || file_len<=chk_size)) begin
                        scan_found_valid  <= 1'b1;
                        scan_found_sector <= scan_sector;
                        scan_found_total  <= scan_found_total + 3'd1;

                        if ((scan_found_total + 3'd1 >= scan_target_count) || (next_match_sector_r > scan_max_sector)) begin
                            scan_done        <= 1'b1;
                            state            <= ST_IDLE;
                            sd_sec_read_addr <= next_match_sector_r;
                            scan_sector      <= next_match_sector_r;
                        end else begin
                            sd_sec_read_addr <= next_match_sector_r;
                            scan_sector      <= next_match_sector_r;
                        end
                    end else begin
                        if (scan_sector >= scan_max_sector) begin
                            scan_done <= 1'b1;
                            state     <= ST_IDLE;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_miss;
                            scan_sector      <= next_scan_sector_if_miss;
                        end
                    end
                end
            end

            // -------- 上电 FAT32 定位：MBR -> BPB -> 根目录 --------
            // 只读，不写盘。找到的 LBA 通过 scan_found_* 发出去，
            // 与原来 ST_SCAN 的输出语义完全一致，所以上层 sd_card_bmp 不用改。
            ST_FAT_MBR: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    part_sel    <= part_sel_c;   // 只选序号，链路短
                    state       <= ST_FAT_PICK;
                end
            end

            ST_FAT_PICK: begin
                state_code       <= 4'd2;
                sd_sec_read      <= 1'b0;
                part_lba         <= lba_sel;     // 4 路选择，一拍搞定
                sd_sec_read_addr <= lba_sel;
                state            <= ST_FAT_BPB;
            end

            ST_FAT_BPB: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    fat_bpb_ok_r <= fat_bpb_ok;
                    fat_cnt     <= num_fats;
                    fat_area    <= 32'd0;
                    fat_phase   <= 2'd0;
                    base_lba    <= (RELIABLE_MEDIA?part_lba_0:part_lba) + rsvd_sec_cnt;
                    clus_shift  <= clus_shift_c;
                    state       <= ST_FAT_MUL;
                end
            end

            // 四个相位，每拍只做一次加减/移位，避免在 sd_card_clk 上开新违例
            ST_FAT_MUL: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b0;

                if (!fat_bpb_ok_r) begin
                    // BPB 不合法：不指望 FAT32，退化成原来的逐扇区扫描
                    scan_done <= 1'b1;
                    state     <= ST_IDLE;
                end else begin
                    case (fat_phase)
                        // 相位 0：fat_area = NumFATs * FATSz32（顺序累加，不用 *）
                        2'd0: begin
                            if (fat_cnt == 8'd0)
                                fat_phase <= 2'd1;
                            else begin
                                fat_area <= fat_area + fat_sz32;
                                fat_cnt  <= fat_cnt - 8'd1;
                            end
                        end
                        // 相位 1：数据区起始 LBA，并预备 RootClus - 2
                        2'd1: begin
                            data_start <= base_lba + fat_area;
                            if(RELIABLE_MEDIA)begin
                                // Initial root and subsequent file/directory clusters use
                                // the same address engine, avoiding a second wide ALU.
                                walk_cluster<=root_clus[27:0];slow_cluster<=root_clus[27:0];
                                slow_phase<=0;chain_file<=0;pend_chk<=0;state<=ST_CHAIN_SEEK;
                            end else begin
                                root_sub<=root_clus-32'd2;root_shift_left<=clus_shift;
                                fat_phase<=2'd2;
                            end
                        end
                        // 相位 2：根目录 cluster 的扇区偏移
                        2'd2: if(!RELIABLE_MEDIA)begin
                            if(RELIABLE_MEDIA && root_shift_left!=0)begin
                                root_sub<=root_sub<<1;root_shift_left<=root_shift_left-1'b1;
                            end else begin
                                root_off<=RELIABLE_MEDIA?root_sub:(root_sub<<clus_shift);
                                fat_phase<=3;
                            end
                        end
                        // 相位 3：根目录起始 LBA，开始按扇区读
                        default: if(!RELIABLE_MEDIA)begin
                            resume_entry     <= 5'd0;   // 全新一轮，不跳过任何项
                            pend_chk         <= 1'b0;
                            root_lba         <= data_start + root_off;
                            root_sector      <= data_start + root_off;
                            sd_sec_read_addr <= data_start + root_off;
                            walk_cluster<=root_clus[27:0];slow_cluster<=root_clus[27:0];slow_phase<=0;
                            root_sec_budget  <= (sec_per_clus > ROOT_SEC_MAX)
                                                ? ROOT_SEC_MAX : sec_per_clus;
                            state            <= ST_FAT_READ;
                        end
                    endcase
                end
            end

            ST_FAT_READ: begin
                state_code  <= 4'd2;
                // ★ 扇区一读完就必须立刻压低 sd_sec_read，直到 fat_sec_done。
                //
                // sd_card_sec_read_write 在 S_READ_END 的**下一拍**就回到
                // S_WAIT_READ_WRITE，只要那时 sd_sec_read 还是 1，它就会立刻再发一条
                // CMD17，并把 sec_addr 锁存成**当时**的 sd_sec_read_addr。
                // 而我们要等 16 拍（fat_end_dly，用来收齐本扇区最后几项）才会把地址
                // 改成下一扇区 / chk_lba —— 到那时命令早就按旧地址发出去了：
                //   * 换扇区时 = 又读了一遍当前扇区 -> 同一项反复命中，死循环
                //   * 去校验时 = 读的是根目录而不是候选文件 -> chk_0/chk_1 是根目录的
                //     头两个字节，所有候选都被判成"不是 BMP"，最后退化成线性扫描
                // 两个坑实测都踩过。sd_sec_read_end 当拍压下、fat_end_dly 归零后再抬起，
                // 中间控制器一直停在 S_WAIT_READ_WRITE，地址才来得及更新。
                sd_sec_read <= (pend_chk || (fat_end_dly != 5'd0) || sd_sec_read_end)
                               ? 1'b0 : 1'b1;

                // 目录项命中：先只记下来。必须等本扇区读完再切走 ——
                // 命中是在扇区中途出来的，这时候切走会让下面 ST_BMP_CHK
                // 看到的是「根目录这个扇区」的 sd_sec_read_end，而不是候选文件的。
                // 一个扇区里可能有多个候选，只记最早的那个，验完再回来接着找。
                if (fat_hit && !pend_chk) begin
                    chk_lba       <= fat_hit_lba;chk_cluster<=fat_hit_cluster;chk_slot<=fat_hit_slot;chk_size<=ent_size;
                    resume_sector <= root_sector;
                    resume_entry  <= {1'b0, fat_hit_idx} + 5'd1;
                    pend_chk      <= 1'b1;
                end

                // fat_sec_done 比 sd_sec_read_end 晚 16 拍，
                // 确保本扇区最后一个目录项的命中已经发出去
                if (fat_sec_done) begin
                    sd_sec_read <= 1'b0;

                    if (pend_chk) begin
                        sd_sec_read_addr <= chk_lba;
                        pend_chk         <= 1'b0;
                        state            <= ST_BMP_CHK;
                    end else if (fat_found_cnt >= scan_target_count) begin
                        scan_done <= 1'b1;          // 凑满 4 张
                        state     <= ST_IDLE;
                    end else if(RELIABLE_MEDIA && !fat_eod && root_sec_budget<=1 && directory_sectors<4095)begin
                        query_cluster<=walk_cluster;chain_file<=0;slow_query<=0;state<=ST_CHAIN_PREP;
                    end else if (fat_eod || (root_sec_budget <= 8'd1)) begin
                        // 整个根目录扫完了
                        // Zero found is also a terminal result.  The upper
                        // layer owns retry/recovery, so do not walk stale
                        // physical sectors looking for old BMPs.
                        scan_done <= 1'b1;
                        state     <= ST_IDLE;
                    end else begin
                        resume_entry     <= 5'd0;   // 换扇区，不再跳过任何项
                        root_sec_budget  <= root_sec_budget - 8'd1;directory_sectors<=directory_sectors+1'b1;
                        root_sector      <= root_sector + 32'd1;
                        sd_sec_read_addr <= root_sector + 32'd1;
                    end
                end
            end

            // 读候选文件的第一个扇区，确认头两个字节是 'B''M' 才认。
            // 少了这一步，卡上那些被 sync_to_sd.py 改成 'XX' 的僵尸文件
            // （目录项没动，名字/扩展名/尺寸全都对）会被当成有效图。
            ST_BMP_CHK: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;

                    if (header_ok_r && !read_fail && (!RELIABLE_MEDIA || file_len<=chk_size)) begin
                        scan_found_valid  <= 1'b1;
                        scan_found_sector <= RELIABLE_MEDIA?{4'd0,chk_cluster}:chk_lba;
                        scan_found_slot<=chk_slot;if(RELIABLE_MEDIA)named_seen[chk_slot]<=1'b1;
                        scan_found_total  <= scan_found_total + 3'd1;
                        fat_found_cnt     <= fat_found_cnt + 4'd1;

                        if (fat_found_cnt + 4'd1 >= scan_target_count) begin
                            scan_done <= 1'b1;
                            state     <= ST_IDLE;
                        end else begin
                            root_sector      <= resume_sector;
                            sd_sec_read_addr <= resume_sector;
                            state            <= ST_FAT_READ;
                        end
                    end else begin
                        // 不是真 BMP，扔掉，回根目录接着找
                        root_sector      <= resume_sector;
                        sd_sec_read_addr <= resume_sector;
                        state            <= ST_FAT_READ;
                    end
                end
            end

            ST_LOAD_HDR: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (header_ok_r && !read_fail) begin
                        write_req        <= 1'b1;
                        sd_sec_read_addr <= RELIABLE_MEDIA?sd_sec_read_addr:load_sector_latched;
                        state            <= ST_LOAD_WAIT;
                    end else begin
                        state <= ST_IDLE;
                    end
                end
            end

            ST_LOAD_WAIT: begin
                state_code <= 4'd3;
                if (write_req_ack) begin
                    write_req   <= 1'b0;
                    state       <= ST_LOAD_DATA;sectors_remaining<=file_sector_count[23:0];cluster_sector<=0;
                    // 缩放器在此刻复位行/列累加器。此时 width/height 已经是本张图的了。
                    pixel_start <= 1'b1;
                end
            end

            ST_LOAD_DATA: begin
                state_code  <= 4'd4;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    // 终止判据从 file_len 换成"H 行齐了"（见 rowlogic）；
                    // 再加一条 load_overrun 兜住"字节不再来、read_end 却照来"
                    // 那种卡 —— 那一种两个时间型看门狗都看不见（见上面的推导）。
                    if (data_done || load_overrun) begin
                        load_complete <= data_done && !read_fail;
                        state <= ST_IDLE;
                    end else begin
                        sectors_remaining<=sectors_remaining-1'b1;
                        if(RELIABLE_MEDIA && cluster_sector==sec_per_clus-1'b1)begin
                            query_cluster<=walk_cluster;slow_query<=0;chain_header<=0;state<=ST_CHAIN_PREP;
                        end else begin
                            cluster_sector<=cluster_sector+1'b1;
                            sd_sec_read_addr<=sd_sec_read_addr+1'b1;
                        end
                    end
                end
            end

            ST_CHAIN_PREP:begin
                sd_sec_read<=0;sd_sec_read_addr<=base_lba+{11'd0,query_cluster[27:7]};state<=ST_CHAIN_READ;
            end
            ST_CHAIN_READ:begin
                sd_sec_read<=1;
                if(sd_sec_read_end)begin sd_sec_read<=0;state<=ST_CHAIN_CHECK;end
            end
            ST_CHAIN_CHECK:begin
                sd_sec_read<=0;
                // EOC terminates directory scanning. A premature EOC or cycle
                // during a file read returns idle without load_complete.
                if(!chain_valid || (slow_query ? chain_next==pending_next : chain_next==slow_cluster))begin
                    if(!chain_file)scan_done<=1;state<=ST_IDLE;
                end else if(slow_query)begin
                    slow_cluster<=chain_next;walk_cluster<=pending_next;slow_query<=0;slow_phase<=0;state<=ST_CHAIN_SEEK;
                end else if(slow_phase)begin
                    pending_next<=chain_next;query_cluster<=slow_cluster;slow_query<=1;state<=ST_CHAIN_PREP;
                end else begin walk_cluster<=chain_next;slow_phase<=1;state<=ST_CHAIN_SEEK;end
            end
            ST_CHAIN_SEEK:begin sd_sec_read<=0;chain_start<=1;state<=ST_CHAIN_WAIT;end
            ST_CHAIN_WAIT:begin
                sd_sec_read<=0;
                if(fat_hit)begin
                    sd_sec_read_addr<=fat_hit_lba;
                    if(chain_file)begin
                        if(chain_header)load_sector_latched<=fat_hit_lba;
                        cluster_sector<=0;state<=chain_header?ST_LOAD_HDR:ST_LOAD_DATA;
                    end
                    else begin
                        root_sector<=fat_hit_lba;root_sec_budget<=sec_per_clus;resume_entry<=0;
                        directory_sectors<=directory_sectors+1'b1;state<=ST_FAT_READ;
                    end
                end
            end
            ST_DRAIN: begin
                sd_sec_read <= 1'b0;
                write_req <= 1'b0;
                state_code <= 4'd4;
                if (sd_sec_read_end || !sector_in_flight)
                    state <= ST_IDLE;
            end

            default: begin
                state       <= ST_IDLE;
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;
            end
        endcase

        // ------------------------------------------------------------------
        // A sector ending without any data is a failed transaction.  The SD
        // controller now has bounded recovery paths, so this normally appears
        // after a CMD17 response error or a data-token timeout.  Abort the
        // current operation instead of parsing stale header/FAT registers.
        // ------------------------------------------------------------------
        if (read_fail) begin
            state       <= ST_IDLE;
            state_code  <= 4'd1;
            sd_sec_read <= 1'b0;
            write_req   <= 1'b0;
            pixel_start <= 1'b0;
            load_complete <= 1'b0;
            scan_found_valid <= 1'b0;
            if (state == ST_BMP_CHK) begin
                state <= ST_FAT_READ;
                sd_sec_read_addr <= resume_sector;
                root_sector <= resume_sector;
            end else if (in_scan_wait)
                scan_done <= 1'b1;
        end

        // ------------------------------------------------------------------
        // ★ 载图停滞超时：**放在 case 之后**，用非阻塞赋值覆盖上面选中的状态。
        //
        //  三个载图状态只有一条出口（等 sd_sec_read_end / write_req_ack），
        //  板上一旦扇区读不回来就是永久死锁 —— ready 恒 0，连
        //  sd_card_bmp 的重发都进不去（它要求 bmp_ready）。这里强制回到
        //  ST_IDLE，把 ready 放出来，让外层既有的"记故障码 + 重发同一张"能跑。
        //  这是整条链上**唯一**能保证 bmp_read 总回得到 IDLE 的地方。
        // ------------------------------------------------------------------
        if (stall_expire || load_abort) begin
            state       <= (sector_in_flight && !sd_sec_read_end) ? ST_DRAIN : ST_IDLE;
            state_code  <= 4'd1;      // 回到 IDLE（诊断由 sd_card_bmp 的 load_fault 记）
            sd_sec_read <= 1'b0;
            write_req   <= 1'b0;
            pixel_start <= 1'b0;
            load_complete <= 1'b0;
            if (in_scan_wait)
                scan_done <= 1'b1;
        end
    end
end

endmodule
