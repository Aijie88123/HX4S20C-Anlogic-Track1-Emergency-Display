`timescale 1ns/1ps

// ===========================================================================
// bmp_write_scaler —— 写侧「任意分辨率 -> 640x480」最近邻缩放（扩展3 / C2-a）
//
// 已接入生产 sd_card_bmp。生产缩小时启用相邻水平样本的取整平均，
// 640 宽图片与放大图片保留原最近邻写侧行为；上屏仍为原双线性扫描。
//
// 为什么写侧用最近邻、不用双线性：
//   写侧是"任意源分辨率 -> 640x480"，比例任意（要靠累加器算），双线性在写侧
//   要**源行缓冲**（最大源宽），代价大一个量级。而**上屏那一段 640x480 -> 1280x720
//   已经是双线性**（线 C1）—— 赛题原文只要求"缩放至 HDMI 输出分辨率"，
//   最后一级是真插值。写侧双线性是 C2-b，另立项。
//
// ---------------------------------------------------------------------------
// 算法：全程只有**加、减、比较**，没有除法器、没有乘法器
// ---------------------------------------------------------------------------
//   n_stored = min(W, 640)            // 一行最多往缓冲里放 640 个条目
//
//   整个水平方向的目标是一句话：**输出列 c 取源列 floor(c*W/640)**。
//
//   水平（写侧）—— 决定"哪些源像素留下来"
//     W >= 640（缩小/相等）：抽点，判据是一次加法 + 一次比较
//         keep  <=>  e + 640 > W
//         e_0 = W;  keep 时 e <= e + 640 - W，否则 e <= e + 640
//       （e_i = i*640 - (ceil(i*640/W)-1)*W ∈ (0, W]，留下的恰好 640 个）
//       ⚠️ 不要改回 "acc += 640; if (acc >= W) { acc -= W; 留 }（acc 初值 0）"：
//          那个写法的 e 初值等于 0，等价于"i+1 跨过 W 的倍数才留"，
//          对 W=800 会**丢掉第 0 个源像素、整帧右移一列**。
//     W <  640（放大）：整行都存（存 W 个），放大交给读侧做
//       —— 写口每拍只能写一次，而源像素是按 SD 速率来的、**停不下来**，
//          所以写侧做不到"一个源像素写多个条目"
//
//   水平（读侧）：输出列 c 读缓冲下标 floor(c * n_stored / 640)
//         acc += n_stored; if (acc >= 640) { acc -= 640; idx++ }
//       n_stored = 640 时退化成直通（缩小那一支的写侧已经把 c 对齐好了）
//
//   垂直：输出行 k 取源行 j_k = floor(k * H / 480)
//         acc += H; while (acc >= 480) { acc -= 480; j++ }
//       ⚠️ 这个 while **最多 9 次**（acc < 480，加 H <= 4095 ⇒ acc+H <= 4574，
//          每次减 480 ⇒ 至多 9 次）—— 所以放在状态机里跑几拍就行，
//          **不需要除法器**。反过来按"源行 -> 输出行"写的话迭代次数是 ceil(480/H)，
//          H=1 时要循环 480 次，更不能做。方向选对了，最坏情况才有界。
//
//       已知的取舍：j_k 是**角点对齐**（j_0 = 0、j_479 = floor(479H/480)）。
//       放大时分布很均匀；缩小时（H > 480）图像**最上面 ceil(H/480) 行不会被用到**
//       （1080 -> 480 时约 2 行，0.2%）。这是有意的、写在文档里的取舍，
//       不是 bug —— 换成端点对齐（j_479 = H-1）会让 H=2 这种极端放大退化成
//       "前 479 行全是源行 0"，那才是真的坏。
//
//   方向：BMP 行是**自下而上**存的，输出流也按同样顺序送出，
//       由 frame_fifo_write 的 WRITE_V_FLIP 负责翻正（与现在完全一致）。
//
// ---------------------------------------------------------------------------
// 行缓冲：**3 块** 640x24 轮转（按源行号 % 3）
// ---------------------------------------------------------------------------
//   生产者在写第 j 块，消费者在读第 (j-k) 块。用 3 块的意思是**允许消费者落后两行**。
//
//   速率预算（为什么够）：
//     消费者输出一个源行要 640 * (480/H) 拍（每输出行 640 拍）；
//     生产者收到下一个源行要一个源行的 SD 读取时间。
//     实测整帧 640x480 约 0.4 s @100 MHz = 40M 拍 ⇒ 每个源行约 40M/H 拍，
//     是 640*480/H 的 **130 倍**以上。就算按 SPI 最理想的 8 拍/字节算，
//     宽 640 的源行也要 640*3*8 = 15360 拍，仍远大于一行最多 640*480/H 拍。
//     ⇒ 余量 10~25 倍。
//
//   但**不靠运气**：真被追上了就置粘滞的 `overflow`，而且**继续正常写**
//   （不丢行）。丢行会让这一帧写不满 write_len，而**基线里没有看门狗**
//   （那是被回退掉的 seg2）⇒ 会永久卡死。"撕裂但可观测" 优于 "静默卡死"。
// ===========================================================================
module bmp_write_scaler #(parameter integer ANTIALIAS=0) (
    input  wire        clk,
    input  wire        rst,

    // 源尺寸（来自 BMP 文件头）。合法范围由上游保证：1 <= W,H <= 4095
    input  wire [11:0] src_w,
    input  wire [11:0] src_h,

    // 源像素流（BMP 存储顺序，行 0 = 图像最下一行）
    input  wire        src_sof,       // 一帧的第一个像素：清累加器与行计数
    input  wire        src_valid,
    input  wire [23:0] src_pixel,

    // 输出像素流：一帧**恰好** 640*480 = 307200 个
    output reg         dst_valid,
    output reg  [23:0] dst_pixel,

    // 诊断（粘滞）：生产者追上了消费者。正常尺寸下必须恒 0
    output reg         overflow
);

    localparam integer DST_W = 640;
    localparam integer DST_H = 480;

    // ---- 三块行缓冲，各 640x24 = 15360 位 ----
    // fehdl 指令是承重的：没有它 TD 会用 LUT 搭 RAM（见 video_scanout_720p.v 的记录）
    reg [23:0] line_0 [0:639];  /* fehdl force_ram=1, ram_style="bram" */
    reg [23:0] line_1 [0:639];  /* fehdl force_ram=1, ram_style="bram" */
    reg [23:0] line_2 [0:639];  /* fehdl force_ram=1, ram_style="bram" */

    // ---------------- 生产者（源侧）----------------
    reg [11:0] col;            // 源列 0..W-1
    reg [11:0] row;            // 正在接收的源行 0..H-1
    reg [11:0] loaded_rows;    // 已完成的源行数（0..H）
    reg [1:0]  wr_mod3;        // row % 3
    reg [9:0]  wr_idx;         // 写地址 0..639
    reg [12:0] acc_w;          // 写侧水平累加器
    reg [11:0] n_stored;       // min(W, 640)
    reg [12:0] acc_v;          // 垂直累加器（消费者用）

    // ---------------- 消费者（输出侧）----------------
    reg [11:0] want_row;       // 下一个要输出的源行 j
    reg [1:0]  want_mod3;      // want_row % 3
    reg [9:0]  out_row;        // 已输出的输出行 0..479
    reg [9:0]  rd_idx;         // 输出列 0..639
    reg [9:0]  buf_ptr;        // 读缓冲下标
    reg [12:0] acc_r;          // 读侧水平累加器
    // cstate 从 2 位扩到 3 位：原来的 4 个状态把 2 位用满了，C_READ 是第 5 个。
    // 只在下面加的 C_READ 用得上，其余状态的值**故意保持不变**（小的 diff）。
    reg [2:0]  cstate;
    localparam [2:0] C_IDLE = 3'd0;
    localparam [2:0] C_EMIT = 3'd1;
    localparam [2:0] C_ADD  = 3'd2;
    localparam [2:0] C_SUB  = 3'd3;
    localparam [2:0] C_READ = 3'd4;   // 送完地址的下一拍：取回 rd_data 并输出

    // ⚠️ src_sof 是"同步复位脉冲"，**允许和第一个像素同拍**：
    //    下面这些 *_c 就是"如果这一拍是 sof 那么实际生效的值"。
    //    第一版把 sof 写成一个占用整拍的分支，结果**第一个源像素被吃掉**，
    //    整帧输出整体错开一个像素（tb 的逐像素比对第一拍就报出来了）。
    wire [11:0] col_c   = src_sof ? 12'd0 : col;
    wire [11:0] row_c   = src_sof ? 12'd0 : row;
    wire [1:0]  wm3_c   = src_sof ? 2'd0 : wr_mod3;
    wire [9:0]  widx_c  = src_sof ? 10'd0 : wr_idx;
    // ⚠️ 这里 sof 当拍不能给 0：e 的初值是 **W**，不是 0（见下面的命中判定）。
    //    三处复位点（本行、下面两个 acc_w<= 的赋值）给的都必须是 W。
    wire [12:0] accw_c  = src_sof ? {1'b0, src_w} : acc_w;

    // ---- 写侧命中判定（缩小：哪些源像素留下来）----
    //
    // 目标映射是标准的最近邻：**输出列 c 取源列 floor(c*W/640)**。
    // 等价的"该不该留下第 i 个源像素"判据（推导见下面的 e 递推）是
    //      keep_i  <=>  e_i + 640 > W
    //      e_0 = W;  keep 时 e_{i+1} = e_i + 640 - W，否则 e_{i+1} = e_i + 640
    // 其中 e_i = i*640 - (ceil(i*640/W) - 1)*W ∈ (0, W]。
    //   * 一次加法 + 一次比较，**没有除法、没有循环**（W/640 的循环上限是 6 次，
    //     但源流是不会停的，写侧不能停几拍去算它）
    //   * 留下的个数恰好 640
    //
    // ⚠️ 第一版用的是 `acc += 640; if (acc >= W) { acc -= W; 留 }`（acc 初值 0），
    //    对 W=800 会**把第 0 个源像素丢掉**、整体右移一列 ——
    //    tb 的逐像素比对第一拍就报 got=pat(0,1) want=pat(0,0)。
    //    那个写法等价于"i+1 跨过 W 的倍数才留"，少算了 c=0 那一列。
    wire        decimating = (src_w >= 12'd640);
    // Width settles before SOF. Compute the constant offset separately from
    // the accumulator carry chain. On a same-cycle SOF/first pixel the exact
    // initial value W+640-W is 640, so even a newly changed width is supported.
    reg [12:0] width_delta;
    always @(posedge clk or posedge rst)
        if(rst)width_delta<=13'd0;
        else width_delta<=13'd640-{1'b0,src_w};
    wire [12:0] e_w_next   = {1'b0, accw_c} + 13'd640;
    wire        keep_pixel = (!decimating) || (e_w_next > {1'b0, src_w});
    wire [12:0] acc_w_new  = decimating ? (src_sof ? 13'd640 : (keep_pixel ? (acc_w + width_delta) : e_w_next))
                                        : accw_c;   // 放大：e 不动（初值就是 W，天然 <640）

    // Two-sample horizontal prefilter for reduction. Equal-size images and
    // the first source pixel keep their exact original values.
    reg [23:0] previous_pixel;
    always @(posedge clk or posedge rst)
        if(rst)previous_pixel<=0;
        else if(src_valid)previous_pixel<=src_pixel;
        else if(src_sof)previous_pixel<=0;
    // ceil((a+b)/2) = a[7:1]+b[7:1]+(a[0]|b[0]).
    // Give the seven-bit adder its carry directly, avoiding a second +1 chain.
    function [7:0] rounded_mean;
        input [7:0] a,b;
        reg [7:0] carry;reg [6:0] sum;integer bit_no;
        begin
            carry[0]=a[0]|b[0];
            for(bit_no=0;bit_no<7;bit_no=bit_no+1)begin
                sum[bit_no]=a[bit_no+1]^b[bit_no+1]^carry[bit_no];
                carry[bit_no+1]=(a[bit_no+1]&b[bit_no+1])|
                    ((a[bit_no+1]|b[bit_no+1])&carry[bit_no]);
            end
            rounded_mean={carry[7],sum};
        end
    endfunction
    wire [23:0] smooth_pixel={rounded_mean(src_pixel[23:16],previous_pixel[23:16]),
        rounded_mean(src_pixel[15:8],previous_pixel[15:8]),rounded_mean(src_pixel[7:0],previous_pixel[7:0])};
    wire [23:0] stored_pixel=(ANTIALIAS && src_w>640 && col_c!=0)?smooth_pixel:src_pixel;
    wire [9:0]  wr_addr    = widx_c;
    wire        we_0 = src_valid && keep_pixel && (wm3_c == 2'd0) && (widx_c <= 10'd639);
    wire        we_1 = src_valid && keep_pixel && (wm3_c == 2'd1) && (widx_c <= 10'd639);
    wire        we_2 = src_valid && keep_pixel && (wm3_c == 2'd2) && (widx_c <= 10'd639);

    // ---- 读口：**必须打一拍**（这一条是承重的，不是风格问题）--------------
    //
    // ⚠️ 这里曾经写成纯组合异步读：
    //        wire [23:0] rd_data = (want_mod3==0) ? line_0[buf_ptr] : ...;
    //    结果 TD **一个 BRAM 都没推断出来**，三块行缓存
    //    (3 x 640 x 24 = 46080 位) 被整个搭成了触发器 + LUT 选择器：
    //        bmp_write_scaler:  lut 33078 / seq 46239 / bram 0
    //    整设计 #reg 53201 (上限 19600) / #lut 43906 (上限 19600)，
    //    PnR 直接 PHY-9011 报死，连 .bit 都没生成。
    //
    //    ⚠️ **数组上的 `fehdl force_ram=1` 救不了它**：BRAM 的读口是**同步**的，
    //    "异步读"这个模式本身就不在可推断范围内 —— 问题出在读法，不在 pragma。
    //    pragma 写得是对的、也一直在，但挡不住结构性不可推断。
    //    与 video_scanout_720p.v 的读法对齐（那里也是 `rd_0_b <= line_0[addr]`）。
    //
    //    代价：读口有 1 拍延迟，所以下面的状态机从"1 拍/像素"变成
    //    "2 拍/像素"（C_EMIT 送地址 -> C_READ 取数据）。**吞吐减半可以接受**：
    //    消费者相对生产者本来就有上百倍余量（见 C2A_WRITE_SCALER.md §3），
    //    减半后仍是几十倍。
    reg [23:0] rd_0_b, rd_1_b, rd_2_b;
    reg [1:0]  rd_bank_b;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_0_b <= 24'd0; rd_1_b <= 24'd0; rd_2_b <= 24'd0; rd_bank_b <= 2'd0;
        end
        else begin
            // 地址和"块号"必须**同拍**送进去：块号在行内不变，
            // 但换行那一拍它和 buf_ptr 一起变，分开打拍会错位到上一行的块。
            rd_0_b    <= line_0[buf_ptr];
            rd_1_b    <= line_1[buf_ptr];
            rd_2_b    <= line_2[buf_ptr];
            rd_bank_b <= want_mod3;
        end
    end
    wire [23:0] rd_data = (rd_bank_b == 2'd0) ? rd_0_b :
                          (rd_bank_b == 2'd1) ? rd_1_b : rd_2_b;

    wire [12:0] acc_r_next  = acc_r + {1'b0, n_stored};
    wire        idx_step    = (acc_r_next >= 13'd640);
    wire [12:0] acc_r_new   = idx_step ? (acc_r_next - 13'd640) : acc_r_next;
    wire [9:0]  buf_ptr_next = idx_step ? (buf_ptr + 10'd1) : buf_ptr;

    wire        row_available = (want_row < loaded_rows);
    wire        last_out_col  = (rd_idx == (DST_W - 1));
    wire [12:0] acc_v_add     = acc_v + {1'b0, src_h};

    wire [1:0]  wr_mod3_next   = (wr_mod3   == 2'd2) ? 2'd0 : (wr_mod3   + 2'd1);
    wire [1:0]  want_mod3_next = (want_mod3 == 2'd2) ? 2'd0 : (want_mod3 + 2'd1);

    // 生产者即将覆盖消费者还要用的块。
    //
    // ⚠️ 判据**不是** "块号相同就算冲突"。块的轮转周期是 3，写第 r 行覆盖的是
    //    **第 r-3 行**；只有当消费者连第 r-3 行都还没读完时才是真冲突。
    //    第一版写成 `(wm3_c == want_mod3) && (row_c != want_row)`，
    //    在 want_row 已经远远跑在前面（消费者早就读完了 r-3）时也会误报 ——
    //    实测 320x240 就这么被误判了一次。
    //    正确的判据只看"生产者比消费者超前了几行"：超过 2 行才会绕回同一块。
    //    另外**必须是有符号比较**：帧首那一拍 row_c 刚被 sof 拉回 0、而 want_row
    //    还是上一帧的值（479），无符号相减会得到一个大正数 ⇒ 又是一个误报。
    wire signed [12:0] row_lead = $signed({1'b0, row_c}) - $signed({1'b0, want_row});
    wire        bank_conflict = (row_lead > 13'sd2);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            col         <= 12'd0;
            row         <= 12'd0;
            loaded_rows <= 12'd0;
            wr_mod3     <= 2'd0;
            wr_idx      <= 10'd0;
            acc_w       <= 13'd0;
            n_stored    <= 12'd640;
            acc_v       <= 13'd0;
            want_row    <= 12'd0;
            want_mod3   <= 2'd0;
            out_row     <= 10'd0;
            rd_idx      <= 10'd0;
            buf_ptr     <= 10'd0;
            acc_r       <= 13'd0;
            cstate      <= C_IDLE;
            dst_valid   <= 1'b0;
            dst_pixel   <= 24'd0;
            overflow    <= 1'b0;
        end
        else begin
            dst_valid <= 1'b0;

            // ==========================================================
            // 消费者：按 j_k = floor(k*H/480) 输出 480 个输出行
            // ==========================================================
            if (src_sof) begin
                acc_v     <= 13'd0;
                want_row  <= 12'd0;
                want_mod3 <= 2'd0;
                out_row   <= 10'd0;
                rd_idx    <= 10'd0;
                buf_ptr   <= 10'd0;
                acc_r     <= 13'd0;
                cstate    <= C_IDLE;
                // ⚠️ overflow 必须**每帧清一次**，不能真·粘滞到永远：
                //    否则第一帧置起之后再也不会产生上升沿，
                //    "本帧有没有被追上"这个信息就丢了 ——
                //    实测 tb 的 A/B 用例（故意的极端喂法）因此报"该溢出却没溢出"。
                overflow  <= 1'b0;
            end
            else begin
                case (cstate)
                    // 输出行 k 用源行 j_k。acc_v 的初值 0 ⇒ j_0 = 0 ✓
                    C_IDLE: if (row_available && (out_row < DST_H))
                                cstate <= C_EMIT;

                    // ⚠️ 这一支**只送地址，绝不能置 dst_valid**：
                    //    这里的 rd_data 还是**上一拍地址**对应的数据（读口打了一拍），
                    //    在这儿发一拍就是"每个像素发两拍、第一拍配对错位的像素" ——
                    //    实测 1280x720 那一例输出数**恰好 614400 = 2 x 307200**，
                    //    逐像素比对也整体错开一格。数据只在 C_READ 发。
                    C_EMIT: begin
                        cstate <= C_READ;
                    end

                    // 读口打了一拍，所以数据在这里才到。
                    // 代价是 2 拍/像素（原来 1 拍），吞吐减半 —— 余量足够，见读口注释。
                    C_READ: begin
                        dst_valid <= 1'b1;
                        dst_pixel <= rd_data;
                        acc_r     <= acc_r_new;
                        buf_ptr   <= buf_ptr_next;
                        if (last_out_col) begin
                            rd_idx  <= 10'd0;
                            acc_r   <= 13'd0;
                            buf_ptr <= 10'd0;
                            out_row <= out_row + 10'd1;
                            cstate  <= C_ADD;
                        end
                        else begin
                            rd_idx <= rd_idx + 10'd1;
                            cstate <= C_EMIT;
                        end
                    end

                    // ⚠️ 顺序不能反：必须**先加 H 再减 480**。
                    //    反过来写（先判 acc_v>=480 再累加）会让 j_1 少算一行 ——
                    //    因为 acc_v 的初值是 0，第一次判"够不够减"必然是假。
                    C_ADD: begin
                        acc_v  <= acc_v_add;
                        cstate <= C_SUB;
                    end

                    // 能减几个 480 就减几个：acc < 480，加 H <= 4095 ⇒ 至多 9 次
                    C_SUB: begin
                        if (acc_v >= 13'd480) begin
                            acc_v     <= acc_v - 13'd480;
                            want_row  <= want_row + 12'd1;
                            want_mod3 <= want_mod3_next;
                        end
                        // ⚠️ 这一支必须**重新查 out_row**，不能无脑回 C_EMIT：
                        //    C_EMIT -> C_ADD -> C_SUB -> C_EMIT 这个环**不经过 C_IDLE**，
                        //    第一版就是因此把 480 行的上限彻底绕过去了 ——
                        //    一帧多吐了 60 多万个像素（identity 用例 915387 != 307200）。
                        // ⚠️ 这里**必须回 C_IDLE**，不能直接回 C_EMIT：
                        //    want_row 是刚刚才更新（非阻塞）的，本拍判 row_available
                        //    读到的还是旧值，直接进 C_EMIT 会拿一个**还没装载的源行**
                        //    去读行缓冲 —— 实测整行读出 xxxxxx。
                        //    绕一趟 C_IDLE 多花 1 拍/输出行（一帧 480 拍），可以忽略。
                        else begin
                            cstate <= C_IDLE;
                        end
                    end

                    default: cstate <= C_IDLE;
                endcase
            end

            // ==========================================================
            // 生产者：源像素 -> 行缓冲
            //   注意用 *_c（sof 当拍取复位值），所以 sof 与首个像素可以同拍
            // ==========================================================
            if (src_valid) begin
                // ⚠️ sof 与首个像素同拍时，下面这个 pre-assignment 是**唯一**
                //    把 row / loaded_rows / wr_mod3 拉回 0 的地方 ——
                //    末尾的 `else if (src_sof)` 分支在 src_valid 那一拍根本不会执行。
                //    漏了它的后果实测是：上一帧的 row=480 带进下一帧，
                //    整个下一帧的块号全错（bank_conflict 在第二拍就误报）。
                if (src_sof) begin
                    row         <= 12'd0;
                    loaded_rows <= 12'd0;
                    wr_mod3     <= 2'd0;
                    // e 的初值是 **W**，不是 0（见命中判定的推导）——
                    // 初值错了会把第 0 个源像素丢掉、整帧右移一列。
                    acc_w       <= {1'b0, src_w};
                end

                if ((col_c == 12'd0) && bank_conflict)
                    overflow <= 1'b1;

                if (keep_pixel && (widx_c <= 10'd639))
                    wr_idx <= widx_c + 10'd1;
                acc_w <= acc_w_new;

                if (col_c == (src_w - 12'd1)) begin
                    col         <= 12'd0;
                    wr_idx      <= 10'd0;
                    acc_w       <= {1'b0, src_w};   // 每行重新起 e
                    row         <= row_c + 12'd1;
                    loaded_rows <= (src_sof ? 12'd0 : loaded_rows) + 12'd1;
                    wr_mod3     <= (wm3_c == 2'd2) ? 2'd0 : (wm3_c + 2'd1);
                end
                else begin
                    col <= col_c + 12'd1;
                end
            end
            else if (src_sof) begin
                col         <= 12'd0;
                row         <= 12'd0;
                loaded_rows <= 12'd0;
                wr_mod3     <= 2'd0;
                wr_idx      <= 10'd0;
                acc_w       <= {1'b0, src_w};
            end

            if (src_sof)
                n_stored <= (src_w >= 12'd640) ? 12'd640 : src_w;
        end
    end

    always @(posedge clk) begin
        if (we_0) line_0[wr_addr] <= stored_pixel;
        if (we_1) line_1[wr_addr] <= stored_pixel;
        if (we_2) line_2[wr_addr] <= stored_pixel;
    end

endmodule

// ===========================================================================
// bmp_write_scaler_bilinear —— 写侧「任意分辨率 -> 640x480」双线性缩放
//
// 这一级放在 SD 像素流和 SDRAM 帧缓存之间。原来的
// `bmp_write_scaler` 保持不动，继续作为最近邻参考和回归门；本模块只改变
// 写侧采样质量，不改变 bmp_read、帧缓存、按键、转场或 HDMI 输出协议。
//
// 关键约束：一帧必须恰好输出 640*480 = 307200 个像素。frame_fifo_write
// 的完成判据没有余量，少一个像素整帧就提交不了，所以下面所有状态迁移都
// 以 `out_row == 480` / `out_col == 639` 为硬边界。
//
// 算法（八相位双线性）：
//   x = c * src_w / 640,  y = k * src_h / 480
//   水平：P0,P1 为 floor(x) / ceil(x)，相位取 8 级
//   垂直：Q0,Q1 为 floor(y) / ceil(y)，相位取 8 级
//   out = mix4(mix4(P0,P1,h), mix4(Q0,Q1,h), v)
//
//   为了不占 DSP，mix4 用「signed 差值 + k 的移位加法 + 四舍五入右移」
//   实现。4 级相位已经足以消除最近邻最明显的台阶，同时把逻辑规模压在
//   行缓存和已有音频 FFT 能承受的范围内。
//
// 行缓存：
//   三块 640x48 的 BRAM，按源行号 %3 轮转。每一条 48 位记录保存相邻
//   两个源像素（正常放大/缩小采样时），因此消费者每拍只需要读一次
//   地址就能同时得到 P0 和 P1。缩小到 640 宽的源图在生产者一侧先做
//   水平双线性抽样，消费者读到的是 640 个水平重采样条目。
//
//   如果生产者真的追上消费者（极小图 + 背靠背喂数），仍只置诊断位并
//   继续写；绝不丢行、绝不静默卡死。这个诊断位会被 sd_card_bmp 的
//   看门狗复用为故障码 4。
// ===========================================================================
module bmp_write_scaler_bilinear (
    input  wire        clk,
    input  wire        rst,

    input  wire [11:0] src_w,
    input  wire [11:0] src_h,

    input  wire        src_sof,
    input  wire        src_valid,
    input  wire [23:0] src_pixel,

    output reg         dst_valid,
    output reg  [23:0] dst_pixel,

    output reg         overflow
);

    localparam integer DST_W = 640;
    localparam integer DST_H = 480;

    localparam [2:0] C_IDLE = 3'd0;
    localparam [2:0] C_PREP = 3'd1;
    localparam [2:0] C_EMIT = 3'd2;
    localparam [2:0] C_ADV  = 3'd3;
    localparam [2:0] C_SUB  = 3'd4;
    localparam [2:0] C_HSEL = 3'd5;
    localparam [2:0] C_FLUSH= 3'd6;
    localparam [2:0] C_HMIX = 3'd7;

    // ------------------------------------------------------------------
    // 8-bit interpolation helpers.
    // ------------------------------------------------------------------
    function [2:0] phase4_h;
        input [9:0] p;               // 0..639
        begin
            if (p < 10'd160)      phase4_h = 3'd0;
            else if (p < 10'd320) phase4_h = 3'd1;
            else if (p < 10'd480) phase4_h = 3'd2;
            else                  phase4_h = 3'd3;
        end
    endfunction

    function [2:0] phase4_v;
        input [9:0] p;               // 0..479
        begin
            if (p < 10'd120)      phase4_v = 3'd0;
            else if (p < 10'd240) phase4_v = 3'd1;
            else if (p < 10'd360) phase4_v = 3'd2;
            else                  phase4_v = 3'd3;
        end
    endfunction

    // mix4(a,b,k) = round((a*(4-k) + b*k) / 4), k in [0,3].
    // The difference is widened to 9 bits before subtraction so negative
    // interpolation never wraps. k*diff is a small shift/add tree; no
    // multiplier is inferred.
    function [7:0] mix4;
        input [7:0] a;
        input [7:0] b;
        input [2:0] k;
        reg signed [8:0]  d;
        reg signed [12:0] p;
        begin
            d = $signed({1'b0, b}) - $signed({1'b0, a});
            case (k)
                3'd0: p = 13'sd0;
                3'd1: p = d;
                3'd2: p = d << 1;
                default: p = (d << 1) + d;
            endcase
            mix4 = a + ((p + 13'sd2) >>> 2);
        end
    endfunction

    function [23:0] mix24;
        input [23:0] a;
        input [23:0] b;
        input [2:0]  k;
        begin
            mix24 = {mix4(a[23:16], b[23:16], k),
                     mix4(a[15:8],  b[15:8],  k),
                     mix4(a[7:0],   b[7:0],   k)};
        end
    endfunction

    // floor(x/640) for x <= 4095, without a divider/multiplier.
    // 640 = 128*5, so floor(x/640) = floor(floor(x/128)/5).
    function [3:0] div640_q;
        input [11:0] x;
        reg [4:0] t;
        begin
            t = x[11:7];
            if (t < 5'd5)       div640_q = 4'd0;
            else if (t < 5'd10) div640_q = 4'd1;
            else if (t < 5'd15) div640_q = 4'd2;
            else if (t < 5'd20) div640_q = 4'd3;
            else if (t < 5'd25) div640_q = 4'd4;
            else if (t < 5'd30) div640_q = 4'd5;
            else                div640_q = 4'd6;
        end
    endfunction

    function [11:0] div640_rem;
        input [11:0] x;
        reg [3:0] q;
        begin
            q = div640_q(x);
            div640_rem = x - (({8'd0, q} << 9) + ({8'd0, q} << 7));
        end
    endfunction

    // Address of the 48-bit line word for output source index idx.
    // For src_w <= 640 each word is {P[idx+1], P[idx]}; the final
    // index reuses the previous word's high half. For src_w > 640 the
    // producer stores a duplicated horizontal sample, so normal address
    // is used everywhere.
    function [9:0] line_addr;
        input [11:0] idx;
        input        pair_mode;
        input [11:0] n;
        begin
            if (pair_mode && (n > 12'd1) && (idx == (n - 12'd1)))
                line_addr = idx[9:0] - 10'd1;
            else
                line_addr = idx[9:0];
        end
    endfunction

    // ------------------------------------------------------------------
    // Three row buffers.  The 48-bit width is deliberate: one BRAM read
    // returns both adjacent source pixels required by horizontal
    // interpolation.  Keep the force_ram pragma: without it TD may build
    // these as distributed RAM and blow the device LUT budget.
    // ------------------------------------------------------------------
    reg [47:0] line_0 [0:639];  /* fehdl force_ram=1, ram_style="bram" */
    reg [47:0] line_1 [0:639];  /* fehdl force_ram=1, ram_style="bram" */
    reg [47:0] line_2 [0:639];  /* fehdl force_ram=1, ram_style="bram" */

    wire        ds_mode   = (src_w > 12'd640);
    wire        pair_mode = (src_w <= 12'd640);
    wire [11:0] n_stored  = ds_mode ? 12'd640 : src_w;
    wire [3:0]  div_q     = div640_q(src_w);
    wire [11:0] div_r     = div640_rem(src_w);

    // ------------------------------------------------------------------
    // Producer: source pixels -> 640 horizontal entries.
    // ------------------------------------------------------------------
    reg [11:0] p_col;
    reg [11:0] p_row;
    reg [11:0] p_loaded;
    reg [1:0]  p_wr_mod3;
    reg [11:0] p_h_out;
    reg [11:0] p_h_idx;
    reg [9:0]  p_h_phase;
    reg [23:0] p_prev;

    reg        wr_en_q;
    reg        row_done_q;
    reg [9:0]  wr_addr_q;
    reg [47:0] wr_data_q;
    reg [1:0]  wr_bank_q;
    reg        wr_en_s1;
    reg        row_done_s1;
    reg        wr_is_ds_s1;
    reg        wr_single_s1;
    reg [9:0]  wr_addr_s1;
    reg [1:0]  wr_bank_s1;
    reg [23:0] wr_a_s1;
    reg [23:0] wr_b_s1;
    reg [2:0]  wr_k_s1;
    reg        wr_en_s2;
    reg        row_done_s2;
    reg        wr_is_ds_s2;
    reg        wr_single_s2;
    reg [9:0]  wr_addr_s2;
    reg [1:0]  wr_bank_s2;
    reg [23:0] wr_a_s2;
    reg [23:0] wr_b_s2;
    reg [2:0]  wr_k_s2;

    wire [11:0] col_c  = src_sof ? 12'd0 : p_col;
    wire [11:0] row_c  = src_sof ? 12'd0 : p_row;
    wire [11:0] out_c  = src_sof ? 12'd0 : p_h_out;
    wire [11:0] idx_c  = src_sof ? 12'd0 : p_h_idx;
    wire [9:0]  ph_c   = src_sof ? 10'd0 : p_h_phase;
    wire [23:0] prev_c = src_sof ? 24'd0 : p_prev;
    wire [1:0]  wm3_c  = src_sof ? 2'd0 : p_wr_mod3;

    // Advance c -> c+1 in the horizontal accumulator:
    //   idx = floor(c*src_w/640), phase = c*src_w mod 640
    wire [12:0] ds_sum   = {3'b0, ph_c} + {1'b0, div_r};
    wire        ds_carry = (ds_sum >= 13'd640);
    wire [11:0] ds_next_idx = idx_c + {8'd0, div_q} + (ds_carry ? 12'd1 : 12'd0);
    wire [9:0]  ds_next_phase = ds_carry ? (ds_sum[9:0] - 10'd640)
                                          : ds_sum[9:0];

    // For a downscaled row, complete one output sample when the source
    // stream has reached the second endpoint (or the exact endpoint for
    // an integer phase). Each input pixel completes at most one sample.
    wire ds_exact     = (ph_c == 10'd0);
    wire ds_complete  = (out_c < 12'd640) &&
                        ((ds_exact && (col_c == idx_c)) ||
                         (!ds_exact && (col_c == (idx_c + 12'd1))));
    wire [23:0] ds_prev = ds_exact ? src_pixel : prev_c;
    wire [23:0] ds_sample = mix24(ds_prev, src_pixel, phase4_h(ph_c));

    // For src_w <= 640, the producer writes overlapping pairs:
    //   line[i] = {P[i+1], P[i]}
    // The final word is only needed for n == 1; for n >= 2 the consumer
    // recovers P[n-1] from the high half of word n-2.
    wire [9:0]  raw_addr = (src_w == 12'd1) ? 10'd0 : (col_c[9:0] - 10'd1);
    wire [47:0] raw_word = (src_w == 12'd1) ? {src_pixel, src_pixel}
                                             : {src_pixel, prev_c};
    wire raw_write = (!ds_mode) &&
                     ((src_w == 12'd1) || (col_c != 12'd0));

    wire producer_write = src_valid && (ds_mode ? ds_complete : raw_write);
    wire producer_done  = src_valid && (col_c == (src_w - 12'd1));
    wire [9:0]  producer_addr = ds_mode ? out_c[9:0] : raw_addr;
    wire [47:0] producer_data = ds_mode ? {ds_sample, ds_sample} : raw_word;

    wire [1:0] p_wr_mod3_next = (wm3_c == 2'd2) ? 2'd0
                                                : (wm3_c + 2'd1);

    // ------------------------------------------------------------------
    // Consumer: 640x480 output, one pixel per C_EMIT cycle.
    // The address register runs one pixel ahead of the arithmetic; C_PREP
    // gives the BRAM read port its first address for the row.
    // ------------------------------------------------------------------
    reg [2:0]  cstate;
    reg [8:0]  out_row;
    reg [9:0]  out_col;
    reg [11:0] h_idx;
    reg [9:0]  h_phase;
    reg [12:0] v_acc;
    reg [12:0] want_row;
    reg [1:0]  want_mod3;
    reg [9:0]  rd_addr;
    reg [1:0]  rd_cur_bank_q;
    reg [1:0]  rd_next_bank_q;
    reg        consumer_row_active;

    reg [47:0] rd_0_b;
    reg [47:0] rd_1_b;
    reg [47:0] rd_2_b;
    reg [1:0]  rd_cur_bank_b;
    reg [1:0]  rd_next_bank_b;

    wire [47:0] rd_word_cur = (rd_cur_bank_b == 2'd0) ? rd_0_b :
                              (rd_cur_bank_b == 2'd1) ? rd_1_b : rd_2_b;
    wire [47:0] rd_word_nxt = (rd_next_bank_b == 2'd0) ? rd_0_b :
                              (rd_next_bank_b == 2'd1) ? rd_1_b : rd_2_b;

    wire [23:0] word_cur_lo = rd_word_cur[23:0];
    wire [23:0] word_cur_hi = rd_word_cur[47:24];
    wire [23:0] word_nxt_lo = rd_word_nxt[23:0];
    wire [23:0] word_nxt_hi = rd_word_nxt[47:24];

    // Registered interpolation stage. C_EMIT captures the two row-buffer
    // words and their phase controls; C_REQ then does the two blend stages
    // and writes dst_pixel. This keeps the BRAM-read/address cone out of
    // the arithmetic path (the first routed build failed at -17.6 ns on
    // exactly that combined cone).
    reg [47:0] calc_word_cur;
    reg [47:0] calc_word_nxt;
    reg        calc_pair_last;
    reg [2:0]  calc_h_weight;
    reg [2:0]  calc_v_weight;
    reg        calc_last_col;
    reg        calc_last_row;
    reg [23:0] hcur_q;
    reg [23:0] hnxt_q;
    reg [23:0] sel_cur_p0;
    reg [23:0] sel_cur_p1;
    reg [23:0] sel_nxt_p0;
    reg [23:0] sel_nxt_p1;
    reg [2:0]  sel_h_weight;
    reg [2:0]  vweight_q;
    reg        hvalid_q;
    reg        last_col_q;
    reg        last_row_q;
    reg [11:0] hpre_idx_q;
    reg [9:0]  hpre_phase_q;

    wire pair_last_now = pair_mode && (n_stored > 12'd1) &&
                         (h_idx == (n_stored - 12'd1));
    wire v_last_now = (want_row == (src_h - 12'd1));
    wire [2:0] h_weight_now = pair_last_now ? 3'd0 : phase4_h(h_phase);
    wire [2:0] v_weight_now = v_last_now ? 3'd0 : phase4_v(v_acc[9:0]);

    wire [23:0] calc_cur_lo = calc_word_cur[23:0];
    wire [23:0] calc_cur_hi = calc_word_cur[47:24];
    wire [23:0] calc_nxt_lo = calc_word_nxt[23:0];
    wire [23:0] calc_nxt_hi = calc_word_nxt[47:24];
    wire [23:0] vert_pixel = mix24(hcur_q, hnxt_q, vweight_q);

    wire [12:0] h_sum_next = {1'b0, h_phase} + {1'b0, n_stored};
    wire        h_carry_next = (h_sum_next >= 13'd640);
    wire [11:0] h_idx_next = h_idx + (h_carry_next ? 12'd1 : 12'd0);
    wire [9:0]  h_phase_next = h_carry_next ?
                               (h_sum_next[9:0] - 10'd640) :
                               h_sum_next[9:0];
    wire [9:0]  h_addr_next = line_addr(h_idx_next, pair_mode, n_stored);

    wire [1:0] want_mod3_next = (want_mod3 == 2'd2) ? 2'd0
                                                     : (want_mod3 + 2'd1);
    wire       last_out_col = (out_col == (DST_W - 1));
    wire       last_out_row = (out_row == (DST_H - 1));
    wire       row_available = (want_row < p_loaded) &&
                               (v_last_now || ((want_row + 12'd1) < p_loaded));

    // At the last pixel of an output row the consumer has already
    // captured the word it needs; the producer may safely start the
    // row that overwrites that now-finished source row. Between rows
    // one extra row of lead is therefore legal.
    wire consumer_row_active_eff = consumer_row_active &&
                                   !((cstate == C_EMIT) && last_out_col);
    wire signed [12:0] p_lead = $signed({1'b0, row_c}) -
                                $signed({1'b0, want_row});
    wire producer_conflict = (p_lead > (consumer_row_active_eff ? 13'sd2
                                                                 : 13'sd3));

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            p_col      <= 12'd0;
            p_row      <= 12'd0;
            p_loaded   <= 12'd0;
            p_wr_mod3  <= 2'd0;
            p_h_out    <= 12'd0;
            p_h_idx    <= 12'd0;
            p_h_phase  <= 10'd0;
            p_prev     <= 24'd0;
            wr_en_s1   <= 1'b0;
            row_done_s1<= 1'b0;
            wr_is_ds_s1<= 1'b0;
            wr_single_s1<= 1'b0;
            wr_addr_s1 <= 10'd0;
            wr_bank_s1 <= 2'd0;
            wr_a_s1    <= 24'd0;
            wr_b_s1    <= 24'd0;
            wr_k_s1    <= 3'd0;
            overflow   <= 1'b0;

            cstate        <= C_IDLE;
            out_row       <= 9'd0;
            out_col       <= 10'd0;
            h_idx         <= 12'd0;
            h_phase       <= 10'd0;
            v_acc         <= 13'd0;
            want_row      <= 13'd0;
            want_mod3     <= 2'd0;
            rd_addr       <= 10'd0;
            rd_cur_bank_q <= 2'd0;
            rd_next_bank_q<= 2'd0;
            consumer_row_active <= 1'b0;
            calc_word_cur <= 48'd0;
            calc_word_nxt <= 48'd0;
            calc_pair_last<= 1'b0;
            calc_h_weight <= 3'd0;
            calc_v_weight <= 3'd0;
            calc_last_col <= 1'b0;
            calc_last_row <= 1'b0;
            hcur_q        <= 24'd0;
            hnxt_q        <= 24'd0;
            sel_cur_p0    <= 24'd0;
            sel_cur_p1    <= 24'd0;
            sel_nxt_p0    <= 24'd0;
            sel_nxt_p1    <= 24'd0;
            sel_h_weight  <= 3'd0;
            vweight_q     <= 3'd0;
            hvalid_q      <= 1'b0;
            last_col_q    <= 1'b0;
            last_row_q    <= 1'b0;
            hpre_idx_q    <= 12'd0;
            hpre_phase_q  <= 10'd0;
            dst_valid     <= 1'b0;
            dst_pixel     <= 24'd0;
        end
        else begin
            dst_valid <= 1'b0;

            // ---------------- producer state ----------------
            if (src_valid) begin
                // Stage 1: register the raw operands and phase. The
                // actual blending happens in the following cycle, which
                // keeps the long 24-bit shift/add tree off the
                // source-pixel-to-BRAM path.
                wr_en_s1     <= ds_mode ? ds_complete : raw_write;
                row_done_s1  <= producer_done;
                wr_addr_s1   <= ds_mode ? out_c[9:0] : raw_addr;
                wr_bank_s1   <= p_wr_mod3;
                wr_a_s1      <= ds_mode ? ds_prev : prev_c;
                wr_b_s1      <= src_pixel;
                wr_k_s1      <= ds_mode ? phase4_h(ph_c) : 3'd0;
                wr_is_ds_s1  <= ds_mode;
                wr_single_s1 <= (src_w == 12'd1);
                p_prev     <= src_pixel;

                if (producer_done) begin
                    p_col     <= 12'd0;
                    p_row     <= row_c + 12'd1;
                    p_wr_mod3 <= p_wr_mod3_next;
                    p_h_out   <= 12'd0;
                    p_h_idx   <= 12'd0;
                    p_h_phase <= 10'd0;
                end
                else begin
                    p_col <= col_c + 12'd1;
                    // On src_sof this carries the effective row/bank zero
                    // into the first pixel instead of letting the previous
                    // frame's final p_row leak into the new frame.
                    p_row     <= row_c;
                    p_wr_mod3 <= wm3_c;
                    if (ds_mode && ds_complete) begin
                        p_h_out   <= out_c + 12'd1;
                        p_h_idx   <= ds_next_idx;
                        p_h_phase <= ds_next_phase;
                    end
                    else begin
                        p_h_out   <= out_c;
                        p_h_idx   <= idx_c;
                        p_h_phase <= ph_c;
                    end
                end
            end
            else begin
                wr_en_s1    <= 1'b0;
                row_done_s1 <= 1'b0;
            end

            // Do not override the first source pixel's state with the
            // frame-start reset: bmp_read may assert src_sof and
            // src_valid on the same clock. The first pixel must still
            // advance p_col and latch p_prev.
            if (!src_valid && src_sof) begin
                p_col     <= 12'd0;
                p_row     <= 12'd0;
                p_wr_mod3 <= 2'd0;
                p_h_out   <= 12'd0;
                p_h_idx   <= 12'd0;
                p_h_phase <= 10'd0;
                p_prev    <= 24'd0;
            end

            if (src_sof) begin
                p_loaded <= 12'd0;
            end
            else if (row_done_q) begin
                p_loaded <= p_loaded + 12'd1;
            end

            if (src_sof)
                overflow <= 1'b0;
            else if (src_valid && producer_conflict)
                overflow <= 1'b1;

            // ---------------- consumer state ----------------
            case (cstate)
                C_IDLE: begin
                    if ((out_row < DST_H) && row_available) begin
                        rd_addr        <= line_addr(12'd0, pair_mode, n_stored);
                        rd_cur_bank_q  <= want_mod3;
                        rd_next_bank_q <= v_last_now ? want_mod3 : want_mod3_next;
                        out_col        <= 10'd0;
                        h_idx          <= 12'd0;
                        h_phase        <= 10'd0;
                        consumer_row_active <= 1'b1;
                        cstate         <= C_PREP;
                    end
                end

                // One cycle of address setup; the next state sees the
                // BRAM output for the first pixel of this row.
                C_PREP: begin
                    hvalid_q <= 1'b0;
                    // Precompute pixel 1's horizontal coordinate while
                    // pixel 0's row-buffer read is being prepared.
                    hpre_idx_q   <= h_idx_next;
                    hpre_phase_q <= h_phase_next;
                    cstate <= C_EMIT;
                end

                C_EMIT: begin
                    // Output the vertical blend for the *previous* pixel
                    // while capturing the row-buffer word for the current
                    // pixel. This keeps the two arithmetic stages in
                    // separate cycles without reducing throughput to three
                    // cycles per output pixel.
                    if (hvalid_q) begin
                        dst_valid <= 1'b1;
                        dst_pixel <= vert_pixel;
                    end

                    calc_word_cur <= rd_word_cur;
                    calc_word_nxt <= rd_word_nxt;
                    calc_pair_last<= pair_last_now;
                    calc_h_weight <= h_weight_now;
                    calc_v_weight <= v_weight_now;
                    calc_last_col <= last_out_col;
                    calc_last_row <= last_out_row;

                    if (last_out_col) begin
                        consumer_row_active <= 1'b0;
                        cstate <= C_HSEL;
                    end
                    else begin
                        out_col  <= out_col + 10'd1;
                        rd_addr  <= line_addr(hpre_idx_q, pair_mode, n_stored);
                        h_idx    <= hpre_idx_q;
                        h_phase  <= hpre_phase_q;
                        cstate   <= C_HSEL;
                    end
                end

                // Select the two horizontal operands and advance the
                // coordinate prefetch. This removes the wide operand mux
                // from the interpolation adder tree.
                C_HSEL: begin
                    sel_cur_p0   <= calc_pair_last ? calc_cur_hi : calc_cur_lo;
                    sel_cur_p1   <= calc_cur_hi;
                    sel_nxt_p0   <= calc_pair_last ? calc_nxt_hi : calc_nxt_lo;
                    sel_nxt_p1   <= calc_nxt_hi;
                    sel_h_weight <= calc_h_weight;
                    hpre_idx_q   <= h_idx_next;
                    hpre_phase_q <= h_phase_next;
                    cstate       <= C_HMIX;
                end

                // Horizontal blend is its own registered stage. Vertical
                // blend then runs in the next C_EMIT while the following
                // source word is fetched.
                C_HMIX: begin
                    hcur_q    <= mix24(sel_cur_p0, sel_cur_p1, sel_h_weight);
                    hnxt_q    <= mix24(sel_nxt_p0, sel_nxt_p1, sel_h_weight);
                    vweight_q <= calc_v_weight;
                    hvalid_q  <= 1'b1;
                    last_col_q<= calc_last_col;
                    last_row_q<= calc_last_row;
                    if (calc_last_col)
                        cstate <= C_FLUSH;
                    else
                        cstate <= C_EMIT;
                end

                C_FLUSH: begin
                    dst_valid <= 1'b1;
                    dst_pixel <= vert_pixel;
                    out_col   <= 10'd0;
                    h_idx     <= 12'd0;
                    h_phase   <= 10'd0;
                    out_row   <= out_row + 9'd1;
                    hvalid_q  <= 1'b0;
                    if (last_row_q)
                        cstate <= C_IDLE;
                    else
                        cstate <= C_ADV;
                end

                C_ADV: begin
                    v_acc  <= v_acc + {1'b0, src_h};
                    cstate <= C_SUB;
                end

                C_SUB: begin
                    if (v_acc >= 13'd480) begin
                        v_acc     <= v_acc - 13'd480;
                        want_row  <= want_row + 12'd1;
                        want_mod3 <= want_mod3_next;
                        cstate    <= C_SUB;
                    end
                    else begin
                        cstate <= C_IDLE;
                    end
                end

                default: cstate <= C_IDLE;
            endcase

            if (src_sof) begin
                cstate        <= C_IDLE;
                out_row       <= 9'd0;
                out_col       <= 10'd0;
                h_idx         <= 12'd0;
                h_phase       <= 10'd0;
                v_acc         <= 13'd0;
                want_row      <= 13'd0;
                want_mod3     <= 2'd0;
                rd_addr       <= 10'd0;
                rd_cur_bank_q <= 2'd0;
                rd_next_bank_q<= 2'd0;
                consumer_row_active <= 1'b0;
                calc_word_cur <= 48'd0;
                calc_word_nxt <= 48'd0;
                calc_pair_last<= 1'b0;
                calc_h_weight <= 3'd0;
                calc_v_weight <= 3'd0;
                calc_last_col <= 1'b0;
                calc_last_row <= 1'b0;
                hcur_q        <= 24'd0;
                hnxt_q        <= 24'd0;
                sel_cur_p0    <= 24'd0;
                sel_cur_p1    <= 24'd0;
                sel_nxt_p0    <= 24'd0;
                sel_nxt_p1    <= 24'd0;
                sel_h_weight  <= 3'd0;
                vweight_q     <= 3'd0;
                hvalid_q      <= 1'b0;
                last_col_q    <= 1'b0;
                last_row_q    <= 1'b0;
                hpre_idx_q    <= 12'd0;
                hpre_phase_q  <= 10'd0;
                dst_valid     <= 1'b0;
                dst_pixel     <= 24'd0;
            end
        end
    end

    // Row-buffer write port. The data word is {P[i+1],P[i]} for
    // upsampling/identity and {sample,sample} for horizontal downsampling.
    // Pipe stage 1 -> stage 2. This is a pure register copy; keeping it
    // separate prevents the large producer blend tree from sharing the
    // same 10 ns path as the source-pixel capture registers.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_en_s2    <= 1'b0;
            row_done_s2 <= 1'b0;
            wr_is_ds_s2 <= 1'b0;
            wr_single_s2<= 1'b0;
            wr_addr_s2  <= 10'd0;
            wr_bank_s2  <= 2'd0;
            wr_a_s2     <= 24'd0;
            wr_b_s2     <= 24'd0;
            wr_k_s2     <= 3'd0;
        end
        else begin
            wr_en_s2    <= wr_en_s1;
            row_done_s2 <= row_done_s1;
            wr_is_ds_s2 <= wr_is_ds_s1;
            wr_single_s2<= wr_single_s1;
            wr_addr_s2  <= wr_addr_s1;
            wr_bank_s2  <= wr_bank_s1;
            wr_a_s2     <= wr_a_s1;
            wr_b_s2     <= wr_b_s1;
            wr_k_s2     <= wr_k_s1;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_en_q   <= 1'b0;
            row_done_q<= 1'b0;
            wr_addr_q <= 10'd0;
            wr_data_q <= 48'd0;
            wr_bank_q <= 2'd0;
        end
        else begin
            wr_en_q    <= wr_en_s2;
            row_done_q <= row_done_s2;
            wr_addr_q  <= wr_addr_s2;
            wr_bank_q  <= wr_bank_s2;
            if (wr_is_ds_s2) begin
                wr_data_q <= {mix24(wr_a_s2, wr_b_s2, wr_k_s2),
                              mix24(wr_a_s2, wr_b_s2, wr_k_s2)};
            end
            else if (wr_single_s2) begin
                wr_data_q <= {wr_b_s2, wr_b_s2};
            end
            else begin
                wr_data_q <= {wr_b_s2, wr_a_s2};
            end
        end
    end

    wire wline_0 = wr_en_q && (wr_bank_q == 2'd0);
    wire wline_1 = wr_en_q && (wr_bank_q == 2'd1);
    wire wline_2 = wr_en_q && (wr_bank_q == 2'd2);

    always @(posedge clk) begin
        if (wline_0) line_0[wr_addr_q] <= wr_data_q;
        if (wline_1) line_1[wr_addr_q] <= wr_data_q;
        if (wline_2) line_2[wr_addr_q] <= wr_data_q;
    end

    // Row-buffer read port. Bank selectors and address are registered
    // together; data is consumed in C_EMIT.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_0_b        <= 48'd0;
            rd_1_b        <= 48'd0;
            rd_2_b        <= 48'd0;
            rd_cur_bank_b <= 2'd0;
            rd_next_bank_b<= 2'd0;
        end
        else begin
            rd_0_b        <= line_0[rd_addr];
            rd_1_b        <= line_1[rd_addr];
            rd_2_b        <= line_2[rd_addr];
            rd_cur_bank_b <= rd_cur_bank_q;
            rd_next_bank_b<= rd_next_bank_q;
        end
    end

endmodule
