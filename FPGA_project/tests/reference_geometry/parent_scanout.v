`timescale 1ns/1ps

// ===========================================================================
// 1280x720 scanout for a 640x480 frame stored in SDRAM —— 输出侧**双线性**缩放
// （扩展3 线 C1，见 doc/SCALING_PLAN.md §3、黄金模型 doc/scaler_model.py）
//
// 比例是"正好"的：水平 2:1、垂直 3:2 —— 所以权重只有 **3 个相位**，
// 不需要通用缩放器（那需要除法器，见 hw/rtl/scaler.v 的反面教材）：
//
//   水平   x 偶 -> out = p[i]                   i = x>>1
//          x 奇 -> out = (p[i] + p[i+1]) >> 1
//   垂直   sy = (2y)/3, frac = (2y)%3
//          frac=0 -> out = A
//          frac=2 -> out = A + ((B-A)*171 + 128) >>> 8   (B 权 2/3)
//          frac=1 -> out = A + ((B-A)*85  + 128) >>> 8   (B 权 1/3)
//
//   * 85 + 171 = 256 —— 两权重**和恰好为 1**：两行相同时输出必须一字不变，
//     否则整屏会偏亮/偏暗（scaler_model.py 已对全部 65536 组 (a,b) 验过）。
//   * 乘 171/85 写成**移位-加法**（171 = 128+32+8+2+1，85 = 64+16+4+1），
//     **不用乘法器** —— 全片只剩 6 个 DSP（23/29），音频 FFT 占着另外 23 个。
//   * 加 128 是四舍五入：截断的最大误差 1.0 LSB，四舍五入 0.5 LSB（实测过）。
//   * 水平方向**不能**复用垂直那套定点式：`(a*128+b*128)>>8` 与 `(a+b)>>1`
//     在奇数和上差 1（32768 个点里有一半点不同）—— 硬件里直接写 (a+b)>>1。
//
// 行缓冲为什么是 **3 块**而不是 2 块：
//   双线性每个输出像素要**同时**读第 sy 行和第 sy+1 行，两块都被占住；
//   而装载第 sy+2 行必须落在**第三块**上，否则会和正在显示的数据打架。
//   装载时刻被 `rows_loaded == cur_src_y + 2` 卡死 ⇒ 写入的块号
//   (sy+2)%3 与读的两块 sy%3、(sy+1)%3 恒不相同（三个余数互异）。
//
// ⚠️ 每个数组上的 `fehdl force_ram` 指令是**承重的**：没有它 TD 会把
//   30720 位的数组实现成分布式 RAM（LUT RAM）。旧版把两行合成一个 2048 深
//    数组时就吃过这个亏（全片 20% 的 LUT）。C1 把 1 块拆成 3 块，**必须**
//    重新用真实综合验证 BRAM 推断（SCALING_PLAN 实验 1）—— 见构建报告。
// ===========================================================================
module geometry_parent_scanout (
    input  wire        clk,
    input  wire        rst,

    output reg         read_req,
    input  wire        read_req_ack,
    output reg         read_en,
    input  wire [31:0] read_data,
    // 读 FIFO 空标志（和本模块同处 video_clk 域，可以直接用）。
    //
    // ★ 为什么必须要它：read_en 拉高是"弹一个字"，read_data 下一拍才有效
    //   （见 frame_read_write.v 的端口注释 "read_data valid next clock"）。
    //   FIFO 空的时候弹，read_data 保持上一次的值 —— 扫描器会把**陈旧数据**
    //   当成本行像素锁进行缓冲，画面就是脏的。
    //
    //   这在实际板子上每帧开头都可能触发：
    //     - frame_fifo_read 在 S_ACK（每帧开头）会 fifo_aclr 清空读 FIFO；
    //     - 本模块 read_req_ack 之后只等 fifo_wait(=48) 拍就开始 pop；
    //     - 而 S_CHECK_FIFO 里有 `~App_wr_busy`，切图时 256 字写突发
    //       （~2 µs，每 ~282 µs 一次）会把读侧整个挡住。
    //   写突发正好落在帧头那几十拍上，FIFO 就是空的，于是顶部若干像素变脏 ——
    //   板上表现为"切图时偶尔抖一下 / 闪一下"，且只在切图时出现。
    input  wire        read_empty,

    output reg         hs,
    output reg         vs,
    output reg         de,
    output wire raw_hs,raw_vs,raw_de,raw_frame_start,
    output wire [11:0] raw_x,raw_y,
    output reg  [23:0] rgb,
    // Aligned with de/rgb: both source rows needed by this pixel were ready.
    output reg         pixel_ready
);

    localparam integer H_ACTIVE = 1280;
    localparam integer H_FP     = 110;
    localparam integer H_SYNC   = 40;
    localparam integer H_BP     = 220;
    localparam integer H_TOTAL  = 1650;

    localparam integer V_ACTIVE = 720;
    localparam integer V_FP     = 5;
    localparam integer V_SYNC   = 5;
    localparam integer V_BP     = 26;
    localparam integer V_TOTAL  = 756;

    localparam integer H_START = H_FP + H_SYNC + H_BP;
    localparam integer V_START = V_FP + V_SYNC + V_BP;

    localparam integer SRC_W = 640;
    localparam integer SRC_H = 480;

    // 垂直权重（8 位小数）= 256 * frac。相位 2 -> 2/3 -> 171；相位 1 -> 1/3 -> 85。
    localparam [7:0] W_TWO_THIRDS = 8'd171;
    localparam [7:0] W_ONE_THIRD  = 8'd85;

    localparam [1:0] LOAD_IDLE  = 2'd0;
    localparam [1:0] LOAD_ISSUE = 2'd1;

    reg [11:0] h_cnt;
    reg [11:0] v_cnt;

    wire hs_raw = (h_cnt >= H_FP) && (h_cnt < (H_FP + H_SYNC));
    wire vs_raw = (v_cnt >= V_FP) && (v_cnt < (V_FP + V_SYNC));
    wire h_active = (h_cnt >= H_START);
    wire v_active = (v_cnt >= V_START) && (v_cnt < V_TOTAL);
    wire de_raw = h_active && v_active;
    wire [11:0] x_raw = h_active ? (h_cnt - H_START) : 12'd0;
    wire [11:0] y_raw = v_active ? (v_cnt - V_START) : 12'd0;

    assign raw_hs=hs_raw;assign raw_vs=vs_raw;assign raw_de=de_raw;assign raw_x=x_raw;assign raw_y=y_raw;
    wire sync_fall_event = (v_cnt == (V_FP + V_SYNC)) && (h_cnt == 12'd0);
    assign raw_frame_start=sync_fall_event;

    // ------------------------------------------------------------------
    // 水平映射：输出列 x -> 源列索引
    //
    // 统一取 ra = (x+1)>>1：
    //     x=2i   -> ra=i     （本拍读到的就是 p[i]，偶数输出直接用它）
    //     x=2i+1 -> ra=i+1   （上一拍读到的是 p[i]，两者取平均）
    // 越界：x=1279 时 ra=640，钳到 639 —— 于是 (p639+p639)>>1 = p639，
    // 正好是"边缘复制"，不会从别的行里读进垃圾。
    // ------------------------------------------------------------------
    wire [11:0] ra_wide  = (x_raw + 12'd1) >> 1;
    wire [9:0]  src_addr = (ra_wide >= 12'd640) ? 10'd639 : ra_wide[9:0];

    reg [5:0]  fifo_wait;
    reg        fifo_ready;

    reg [1:0]  load_state;
    reg        load_pending;
    reg        read_en_d;
    reg        read_empty_d;      // 与 read_en_d 对齐的 FIFO 空标志
    reg [9:0]  load_cnt;
    reg [9:0]  issued;            // 本行已经弹出的字数（真正取到的）
    reg [9:0]  rows_loaded;
    reg [1:0]  rows_mod3;         // rows_loaded % 3 —— 装载落在哪一块
    reg [9:0]  cur_src_y;
    reg [1:0]  vert_phase;
    reg [1:0]  sy_mod3;           // cur_src_y % 3 —— 显示读哪一块

    // 三块行缓冲，按行号 %3 分块。每块 640x24 = 15360 位。
    reg [23:0] line_0 [0:639];  /* fehdl force_ram=1, ram_style="bram" */
    reg [23:0] line_1 [0:639];  /* fehdl force_ram=1, ram_style="bram" */
    reg [23:0] line_2 [0:639];  /* fehdl force_ram=1, ram_style="bram" */

    wire [9:0] next_src_y = cur_src_y + ((vert_phase == 2'd0) ? 10'd0 : 10'd1);
    wire [1:0] next_vert_phase = (vert_phase == 2'd2) ? 2'd0 : (vert_phase + 1'b1);
    wire [1:0] sy_mod3_next   = (sy_mod3   == 2'd2) ? 2'd0 : (sy_mod3   + 1'b1);
    wire [1:0] rows_mod3_next = (rows_mod3 == 2'd2) ? 2'd0 : (rows_mod3 + 1'b1);
    wire       next_src_y_moves = (next_src_y != cur_src_y);

    // 最后一行没有"下一行"：钳掉垂直混合（w 取 0），并且只需要自己一块。
    wire is_last_src_row = (cur_src_y == (SRC_H - 1));
    wire line_ready = is_last_src_row ? (rows_loaded > cur_src_y)
                                      : (rows_loaded > (cur_src_y + 10'd1));

    // 本拍确实从读 FIFO 弹出了一个有效字（read_data 下一拍才有效）。
    // read_en 拉高但 FIFO 恰好空的这一拍不算 —— 那种情况下 FIFO 不弹，
    // read_data 保持旧值，不能当像素用。
    wire pop_now = read_en & ~read_empty;
    wire at_line_start = de_raw && (x_raw == 12'd0);
    wire at_line_end = v_active && (h_cnt == (H_TOTAL - 1));

    // ------------------------------------------------------------------
    // 装载起跑条件
    //
    // 显示第 y 行需要第 sy 与 sy+1 **两行都已就位** ⇒ 装载必须比老版本
    // （最近邻只要 sy 一行）**提前一行**。老版本用
    //   start_next_row = 行首 && rows_loaded == next_src_y
    // 到这里会晚一行拿到 sy+1，所以换成"欠了几行就补几行"：
    //
    //   消隐期（还没开始显示）：预先装 3 行，此时写哪一块都无所谓
    //   有效行：只在**行首**起跑，且 rows_loaded == cur_src_y + 2
    //           —— 目标块 (sy+2)%3 与正在读的两块 sy%3、(sy+1)%3 互异
    //
    // 每 3 行装 2 行，与老版本同一速率（480 行 / 720 行），
    // 所以读 FIFO 的消耗速率不变，不会引入新的下溢风险。
    // ------------------------------------------------------------------
    wire in_vblank = ~v_active;
    wire load_wanted = (rows_loaded < SRC_H) &&
                       (in_vblank ? (rows_loaded < 10'd3)
                                  : (at_line_start && (rows_loaded < (cur_src_y + 10'd3))));

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            h_cnt <= 12'd0;
            v_cnt <= 12'd0;
        end
        else begin
            if (h_cnt == (H_TOTAL - 1)) begin
                h_cnt <= 12'd0;
                if (v_cnt == (V_TOTAL - 1))
                    v_cnt <= 12'd0;
                else
                    v_cnt <= v_cnt + 1'b1;
            end
            else begin
                h_cnt <= h_cnt + 1'b1;
            end
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            read_req  <= 1'b0;
            fifo_wait <= 6'd0;
            fifo_ready <= 1'b0;
        end
        else begin
            if (sync_fall_event) begin
                read_req   <= 1'b1;
                fifo_wait  <= 6'd0;
                fifo_ready <= 1'b0;
            end
            else if (read_req && read_req_ack) begin
                read_req  <= 1'b0;
                fifo_wait <= 6'd48;
            end
            else if (fifo_wait != 6'd0) begin
                fifo_wait <= fifo_wait - 1'b1;
                if (fifo_wait == 6'd1)
                    fifo_ready <= 1'b1;
            end
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            load_state   <= LOAD_IDLE;
            load_pending <= 1'b0;
            load_cnt     <= 10'd0;
            issued       <= 10'd0;
            rows_loaded  <= 10'd0;
            rows_mod3    <= 2'd0;
            cur_src_y    <= 10'd0;
            vert_phase   <= 2'd0;
            sy_mod3      <= 2'd0;
            read_en      <= 1'b0;
            read_en_d    <= 1'b0;
            read_empty_d <= 1'b0;
        end
        else begin
            read_en      <= 1'b0;
            read_en_d    <= read_en;
            read_empty_d <= read_empty;

            if (sync_fall_event) begin
                load_state   <= LOAD_IDLE;
                load_pending <= 1'b1;
                load_cnt     <= 10'd0;
                issued       <= 10'd0;
                rows_loaded  <= 10'd0;
                rows_mod3    <= 2'd0;
                cur_src_y    <= 10'd0;
                vert_phase   <= 2'd0;
                sy_mod3      <= 2'd0;
                read_en      <= 1'b0;
                read_en_d    <= 1'b0;
                read_empty_d <= 1'b1;   // 帧头 FIFO 刚被 aclr 清空
            end
            else begin
                if (at_line_end) begin
                    cur_src_y  <= next_src_y;
                    vert_phase <= next_vert_phase;
                    if (next_src_y_moves)
                        sy_mod3 <= sy_mod3_next;
                end

                if ((load_state == LOAD_IDLE) && load_wanted)
                    load_pending <= 1'b1;

                if ((load_state == LOAD_IDLE) &&
                    load_pending && fifo_ready) begin
                    load_state   <= LOAD_ISSUE;
                    load_pending <= 1'b0;
                    load_cnt     <= 10'd0;
                    issued       <= 10'd0;
                    read_en_d    <= 1'b0;
                    read_en      <= 1'b1;
                end
                else if (load_state == LOAD_ISSUE) begin
                    // ★ 只有 FIFO 当拍确实非空，read_en 弹出来的这一拍才是有效数据
                    //   （read_data 下一拍有效，所以这里用 read_en_d & ~read_empty_d）。
                    if (read_en_d && !read_empty_d)
                        load_cnt <= load_cnt + 1'b1;

                    if (pop_now)
                        issued <= issued + 1'b1;

                    if (load_cnt == SRC_W) begin
                        // 本行 640 个字全部收进行缓冲
                        read_en     <= 1'b0;
                        rows_loaded <= rows_loaded + 1'b1;
                        rows_mod3   <= rows_mod3_next;
                        load_state  <= LOAD_IDLE;
                    end
                    else if ((issued + (pop_now ? 10'd1 : 10'd0)) < SRC_W) begin
                        // FIFO 空就停一拍等数据，非空就继续弹。
                        // SDRAM 读被写突发挡住时本行只会晚一点到，不会灌错像素。
                        //
                        // 判据必须用"已弹出的字数(issued)"而不是"已收进行缓冲
                        // 的字数(load_cnt)"：load_cnt 比 issued 晚两拍，用它收尾会
                        // 每行多发一个读脉冲，把整帧的字流错开一个字
                        // （实测 480 行 → 多吃 480 个字，画面整体错位）。
                        read_en <= ~read_empty;
                    end
                    else begin
                        // 640 个读脉冲已发完，最后一个字还在流水线上
                        read_en <= 1'b0;
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // 行缓冲写口：按 rows_mod3 选块（每块一个独立 write-enable，
    // BRAM 推断要的就是这个形状）
    // ------------------------------------------------------------------
    wire       line_wr_en = (load_state == LOAD_ISSUE) && read_en_d && !read_empty_d;
    wire [9:0] line_wr_addr = load_cnt;
    wire [23:0] line_wr_data = read_data[31:8];
    wire       we_0 = line_wr_en && (rows_mod3 == 2'd0);
    wire       we_1 = line_wr_en && (rows_mod3 == 2'd1);
    wire       we_2 = line_wr_en && (rows_mod3 == 2'd2);

    always @(posedge clk)
        if (we_0) line_0[line_wr_addr] <= line_wr_data;
    always @(posedge clk)
        if (we_1) line_1[line_wr_addr] <= line_wr_data;
    always @(posedge clk)
        if (we_2) line_2[line_wr_addr] <= line_wr_data;

    // ------------------------------------------------------------------
    // 流水线（**5 级**：x_raw@t -> rgb@t+5）
    //
    // ⚠️ 级数是被**真实时序逼出来的**，不是保守：
    //    第一版把"BRAM 输出 -> 选块 -> 水平平均 -> 垂直加权 -> rgb"全放在一个
    //    组合锥里（3 级流水），TD 报出来的最差路径就是
    //      ramread*_syn_*.clkb -> rgb_reg[*]   SWNS **-5.181 ns**、36 个违例端点，
    //    全部在 video_clk（75 MHz / 13.333 ns）—— 也就是说那条链实际跑了 ~18.5 ns。
    //    拆成 5 级之后每一段都只剩 1~2 个逻辑层（见下面的分配）。
    //
    //   stage A (t)   : 地址 / 控制 / 权重相位 / 读哪两块
    //   stage B (t+1) : 行缓冲读口（3 块并行读）
    //   stage B2(t+2) : 选块 mux -> 登记；上一拍的读结果(水平平均用)也在这级打拍
    //   stage C (t+3) : 水平平均 -> 登记
    //   stage D (t+4) : 垂直加权（移位-加法树）-> rgb / hs / vs / de
    //
    // 控制位（line_ctrl_*）与相位位（mix_sel_*）跟着数据一起打拍，
    // 每一级都重新对齐 —— 这是老版本 line_ctrl_a/b 的做法的延长。
    // ------------------------------------------------------------------
    reg [9:0]  line_addr_a;
    reg [1:0]  rb_top_a;
    reg [1:0]  rb_bot_a;
    reg [3:0]  line_ctrl_a;
    reg [3:0]  mix_sel_a;          // {x_odd, is_last_src_row, vert_phase}
    reg [1:0]  rb_top_b, rb_bot_b;
    reg [23:0] rd_0_b, rd_1_b, rd_2_b;
    reg [3:0]  line_ctrl_b, line_ctrl_c, line_ctrl_d;
    reg [3:0]  mix_sel_b, mix_sel_c, mix_sel_d;
    reg [23:0] d_top_r, d_bot_r;
    reg [23:0] d_top_prev, d_bot_prev;
    reg [23:0] h_top_r, h_bot_r;

    // ⚠️ 选块必须用**打了一拍**的 rb_*_b，不能用 stage A 的 rb_*_a。
    //    行缓冲读口在 stage B 才发出（用的是 stage A 打下来的地址），
    //    数据 stage C 才到；而 sy_mod3 是在行末那一拍翻的。用 rb_*_a 的话，
    //    每行**最后一个像素**（x=1279）会拿新行的块去套旧行的数据 ——
    //    实测表现是 479 个错像素、全在 x=1279，很容易被当成"边缘钳位写错"。
    //    旧版把 bank 拼进地址高位、和地址一起打一拍，天然没有这个问题。
    wire [23:0] d_top = (rb_top_b == 2'd0) ? rd_0_b :
                        (rb_top_b == 2'd1) ? rd_1_b : rd_2_b;
    wire [23:0] d_bot = (rb_bot_b == 2'd0) ? rd_0_b :
                        (rb_bot_b == 2'd1) ? rd_1_b : rd_2_b;

    // ---- 水平混合（stage C 组合，只有"1 个加法 + 1 个 mux"一层）----
    wire [8:0] hs_r = {1'b0, d_top_prev[23:16]} + {1'b0, d_top_r[23:16]};
    wire [8:0] hs_g = {1'b0, d_top_prev[15:8]}  + {1'b0, d_top_r[15:8]};
    wire [8:0] hs_b = {1'b0, d_top_prev[7:0]}   + {1'b0, d_top_r[7:0]};
    wire [8:0] hb_r = {1'b0, d_bot_prev[23:16]} + {1'b0, d_bot_r[23:16]};
    wire [8:0] hb_g = {1'b0, d_bot_prev[15:8]}  + {1'b0, d_bot_r[15:8]};
    wire [8:0] hb_b = {1'b0, d_bot_prev[7:0]}   + {1'b0, d_bot_r[7:0]};

    wire [23:0] h_top = mix_sel_c[3] ? {hs_r[8:1], hs_g[8:1], hs_b[8:1]}
                                     : d_top_r;
    wire [23:0] h_bot = mix_sel_c[3] ? {hb_r[8:1], hb_g[8:1], hb_b[8:1]}
                                     : d_bot_r;

    // ---- 垂直混合（stage D 组合，移位-加法，0 乘法器）----
    // ⚠️ 相位号与 frac 的对应关系**不是**想当然的：line y 的 vert_phase = y%3，
    //    而垂直分数 frac = (2y)%3。于是
    //        y%3==1 -> frac=2 -> B 权 2/3 (171)
    //        y%3==2 -> frac=1 -> B 权 1/3 (85)
    //    写反了的话**只有相位 1/2 的行**会错（相位 0 的行本来就 w=0），
    //    肉眼很像是"抖动"而不是"插值错"，很难查 —— tb 里逐像素比对是当场抓住它的。
    wire       v_2thirds = (mix_sel_d[1:0] == 2'd1);   // frac = 2/3 -> B 权 171
    wire       v_1third  = (mix_sel_d[1:0] == 2'd2);   // frac = 1/3 -> B 权 85
    wire       v_bypass  = mix_sel_d[2] | ~(v_2thirds | v_1third);  // 相位 0 / 最后一行

    // 位宽是算过的：|B-A| <= 255 -> 9 位有符号够；
    // |(B-A)*171 + 128| <= 43733 -> 17 位有符号够。
    // Keep the original pipeline and rounding exactly. Three small variable
    // signed products map to the spare DSP blocks instead of cascaded shift
    // adders in the 75 MHz path. Weight and pixel alignment remain unchanged.
    wire signed [8:0] dv_r=$signed({1'b0,h_bot_r[23:16]})-$signed({1'b0,h_top_r[23:16]});
    wire signed [8:0] dv_g=$signed({1'b0,h_bot_r[15:8]})-$signed({1'b0,h_top_r[15:8]});
    wire signed [8:0] dv_b=$signed({1'b0,h_bot_r[7:0]})-$signed({1'b0,h_top_r[7:0]});
    wire signed [8:0] vertical_weight=v_2thirds?9'sd171:9'sd85;
    wire signed [17:0] product_r=dv_r*vertical_weight;
    wire signed [17:0] product_g=dv_g*vertical_weight;
    wire signed [17:0] product_b=dv_b*vertical_weight;
    // floor((p+128)/256) = floor(p/256)+p[7], also for negative p.
    wire [7:0] vm_r=h_top_r[23:16]+product_r[15:8]+product_r[7];
    wire [7:0] vm_g=h_top_r[15:8]+product_g[15:8]+product_g[7];
    wire [7:0] vm_b=h_top_r[7:0]+product_b[15:8]+product_b[7];
    wire [23:0] v_mix = {vm_r, vm_g, vm_b};

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            line_addr_a <= 10'd0;
            rb_top_a    <= 2'd0;
            rb_bot_a    <= 2'd0;
            line_ctrl_a <= 4'd0;
            mix_sel_a   <= 4'd0;
        end
        else begin
            line_addr_a <= src_addr;
            rb_top_a    <= sy_mod3;
            rb_bot_a    <= sy_mod3_next;
            line_ctrl_a <= {hs_raw, vs_raw, de_raw, line_ready};
            mix_sel_a   <= {x_raw[0], is_last_src_row, vert_phase};
        end
    end

    // stage B — 行缓冲读口（3 块并行读，不做任何选择）
    always @(posedge clk) begin
        rd_0_b <= line_0[line_addr_a];
        rd_1_b <= line_1[line_addr_a];
        rd_2_b <= line_2[line_addr_a];
        rb_top_b <= rb_top_a;
        rb_bot_b <= rb_bot_a;
    end

    // stage B2 — 选块 mux 单独打一拍（这一级就是被 -5.181 ns 逼出来的：
    //            选块 mux 与后面的加法树串在一起时，整锥跑了 ~18.5 ns）
    always @(posedge clk) begin
        d_top_r     <= d_top;
        d_bot_r     <= d_bot;
        d_top_prev  <= d_top_r;
        d_bot_prev  <= d_bot_r;
        line_ctrl_b <= line_ctrl_a;
        mix_sel_b   <= mix_sel_a;
    end

    // stage C — 水平平均打一拍
    always @(posedge clk) begin
        h_top_r     <= h_top;
        h_bot_r     <= h_bot;
        line_ctrl_c <= line_ctrl_b;
        mix_sel_c   <= mix_sel_b;
    end

    always @(posedge clk) begin
        line_ctrl_d <= line_ctrl_c;
        mix_sel_d   <= mix_sel_c;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            hs  <= 1'b0;
            vs  <= 1'b0;
            de  <= 1'b0;
            rgb <= 24'd0;
            pixel_ready <= 1'b0;
        end
        else begin
            hs  <= line_ctrl_d[3];
            vs  <= line_ctrl_d[2];
            de  <= line_ctrl_d[1];
            pixel_ready <= line_ctrl_d[0];
            rgb <= (line_ctrl_d[1] && line_ctrl_d[0]) ?
                   (v_bypass ? h_top_r : v_mix) : 24'd0;
        end
    end

endmodule
