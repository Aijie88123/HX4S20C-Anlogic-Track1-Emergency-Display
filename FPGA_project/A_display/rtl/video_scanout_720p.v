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
module video_scanout_720p #(parameter ENABLE_GEOMETRY=0,GEOMETRY_RGB444=0) (
    input  wire        clk,
    input  wire        rst,

    output wire        read_req,
    input  wire        read_req_ack,
    output wire        read_en,
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
    output reg         pixel_ready,
    input wire geometry_active,geometry_flip,
    input wire [11:0] geometry_width,geometry_left,
    input wire [9:0] geometry_height,geometry_top,
    input wire [16:0] geometry_inv_x,geometry_inv_y,
    input wire [20:0] geometry_old_base,geometry_new_base,
    input wire geometry_back_half,geometry_old_rgb444,geometry_new_rgb444,
    output wire geometry_read_rgb444,
    output wire [20:0] geometry_read_base
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


    reg legacy_read_req,legacy_read_en;
    wire geometry_on=ENABLE_GEOMETRY && geometry_active;
    wire geo_req,geo_en;
    wire [1:0] geo_write_bank;
    wire [9:0] geo_write_addr;
    wire geo_write_enable,geo_bg_valid,geo_fg_valid;
    wire [1:0] geo_pair;
    assign read_req=geometry_on?geo_req:legacy_read_req;
    assign read_en=geometry_on?geo_en:legacy_read_en;

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
    reg [23:0] line_3 [0:639];  /* fehdl force_ram=1, ram_style="bram" */

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
    // legacy_read_en 拉高但 FIFO 恰好空的这一拍不算 —— 那种情况下 FIFO 不弹，
    // read_data 保持旧值，不能当像素用。
    wire pop_now = legacy_read_en & ~read_empty;
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
            legacy_read_req  <= 1'b0;
            fifo_wait <= 6'd0;
            fifo_ready <= 1'b0;
        end
        else begin
            if (sync_fall_event) begin
                legacy_read_req   <= 1'b1;
                fifo_wait  <= 6'd0;
                fifo_ready <= 1'b0;
            end
            else if (legacy_read_req && read_req_ack) begin
                legacy_read_req  <= 1'b0;
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
            legacy_read_en      <= 1'b0;
            read_en_d    <= 1'b0;
            read_empty_d <= 1'b0;
        end
        else begin
            legacy_read_en      <= 1'b0;
            read_en_d    <= legacy_read_en;
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
                legacy_read_en      <= 1'b0;
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
                    legacy_read_en      <= 1'b1;
                end
                else if (load_state == LOAD_ISSUE) begin
                    // ★ 只有 FIFO 当拍确实非空，legacy_read_en 弹出来的这一拍才是有效数据
                    //   （read_data 下一拍有效，所以这里用 read_en_d & ~read_empty_d）。
                    if (read_en_d && !read_empty_d)
                        load_cnt <= load_cnt + 1'b1;

                    if (pop_now)
                        issued <= issued + 1'b1;

                    if (load_cnt == SRC_W) begin
                        // 本行 640 个字全部收进行缓冲
                        legacy_read_en     <= 1'b0;
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
                        legacy_read_en <= ~read_empty;
                    end
                    else begin
                        // 640 个读脉冲已发完，最后一个字还在流水线上
                        legacy_read_en <= 1'b0;
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // 行缓冲写口：按 rows_mod3 选块（每块一个独立 write-enable，
    // BRAM 推断要的就是这个形状）
    // ------------------------------------------------------------------
    wire legacy_line_wr_en = (load_state == LOAD_ISSUE) && read_en_d && !read_empty_d;
    wire line_wr_en=geometry_on?geo_write_enable:legacy_line_wr_en;
    wire [9:0] line_wr_addr = geometry_on?geo_write_addr:load_cnt;
    wire [23:0] line_wr_data = read_data[31:8];
    wire       we_0 = line_wr_en && (geometry_on ? geo_write_bank==2'd0 : rows_mod3==2'd0);
    wire       we_1 = line_wr_en && (geometry_on ? geo_write_bank==2'd1 : rows_mod3==2'd1);
    wire       we_2 = line_wr_en && (geometry_on ? geo_write_bank==2'd2 : rows_mod3==2'd2);

    always @(posedge clk)
        if (we_0) line_0[line_wr_addr] <= line_wr_data;
    always @(posedge clk)
        if (we_1) line_1[line_wr_addr] <= line_wr_data;
    always @(posedge clk)
        if (we_2) line_2[line_wr_addr] <= line_wr_data;

    generate if(ENABLE_GEOMETRY)begin: geometry_line_storage
      always @(posedge clk)if(line_wr_en && geometry_on && geo_write_bank==3)line_3[line_wr_addr]<=line_wr_data;
    end endgenerate

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
    wire [23:0] rd_3_b;
    reg geometry_a,geometry_b;
    reg geo_flip_a,geo_flip_b,geo_inside_a,geo_inside_b;
    reg geo_pair_a,geo_pair_b,geo_shape_a,geo_shape_b;
    wire [23:0] legacy_d_top;
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
    assign legacy_d_top = (rb_top_b == 2'd0) ? rd_0_b :
                        (rb_top_b == 2'd1) ? rd_1_b : rd_2_b;
    wire [23:0] d_top=geometry_b ?
      (geo_shape_b ? (geo_pair_b?rd_3_b:rd_1_b) : (geo_pair_b?rd_2_b:rd_0_b)) : legacy_d_top;
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

    wire [11:0] geo_x_ahead=(h_cnt+12'd2>=H_START && h_cnt+12'd2<H_TOTAL)?h_cnt+12'd2-H_START:12'd0;
    reg [11:0] geo_x_delta;
    reg [28:0] geo_x_product;
    wire [16:0] geo_x_index=geo_x_product[28:12];
    reg [9:0] geo_addr_a;
    wire geo_inside=geometry_width!=0 && x_raw>=geometry_left && x_raw<geometry_left+geometry_width &&
      (geometry_flip || (y_raw>=geometry_top && {2'd0,y_raw}<{2'd0,geometry_top}+geometry_height));
    generate if(ENABLE_GEOMETRY)begin: geometry_coordinate
      always @(posedge clk)begin
        geo_x_delta<=geo_x_ahead>=geometry_left?geo_x_ahead-geometry_left:12'd0;
        geo_x_product<=geo_x_delta*geometry_inv_x;
        geo_addr_a<=geo_x_index>=640?10'd639:geo_x_index[9:0];
      end
      reg [23:0] rd3;
      always @(posedge clk)rd3<=line_3[geometry_a?geo_addr_a:line_addr_a];
      assign rd_3_b=rd3;
      geometry_row_reader u_geometry_reader(.clk(clk),.rst(rst),.active(geometry_on),.frame_start(sync_fall_event),
        .line_start(at_line_start),.output_y(y_raw[9:0]),.next_old_y(next_src_y),.flip(geometry_flip),
        .width(geometry_width),.height(geometry_height),.top(geometry_top),.inv_y(geometry_inv_y),
        .old_base(geometry_old_base),.new_base(geometry_new_base),.back_half(geometry_back_half),
        .old_rgb444(GEOMETRY_RGB444 && geometry_old_rgb444),.new_rgb444(GEOMETRY_RGB444 && geometry_new_rgb444),.read_rgb444(geometry_read_rgb444),
        .read_req(geo_req),.read_ack(read_req_ack),.read_en(geo_en),.read_empty(read_empty),
        .read_base(geometry_read_base),.write_enable(geo_write_enable),.write_bank(geo_write_bank),.write_addr(geo_write_addr),
        .background_valid(geo_bg_valid),.foreground_valid(geo_fg_valid),.display_pair(geo_pair));
    end else begin: no_geometry
      assign rd_3_b=24'd0;assign geo_req=0;assign geo_en=0;assign geometry_read_base=0;assign geometry_read_rgb444=0;
      assign geo_write_enable=0;assign geo_write_bank=0;assign geo_write_addr=0;
      assign geo_bg_valid=0;assign geo_fg_valid=0;assign geo_pair=0;
    end endgenerate

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            line_addr_a <= 10'd0;
            rb_top_a    <= 2'd0;
            rb_bot_a    <= 2'd0;
            line_ctrl_a <= 4'd0;
            mix_sel_a   <= 4'd0;
            geometry_a<=0;geo_pair_a<=0;geo_shape_a<=0;geo_flip_a<=0;geo_inside_a<=0;
        end
        else begin
            line_addr_a <= geometry_on ? x_raw[10:1] : src_addr;
            rb_top_a    <= sy_mod3;
            rb_bot_a    <= sy_mod3_next;
            geometry_a<=geometry_on;geo_flip_a<=geometry_flip;geo_inside_a<=geo_inside;
            geo_pair_a<=geo_pair[0];
            geo_shape_a<=geometry_on && !geometry_flip && geo_inside && geo_fg_valid;
            line_ctrl_a <= {hs_raw, vs_raw, de_raw,
              geometry_on ? (geometry_flip ? (!geo_inside || geo_bg_valid) : geo_bg_valid) : line_ready};
            mix_sel_a   <= geometry_on ? 4'b0100 : {x_raw[0], is_last_src_row, vert_phase};
        end
    end

    // stage B — 行缓冲读口（3 块并行读，不做任何选择）
    always @(posedge clk) begin
        rd_0_b <= line_0[geometry_a && geometry_flip ? geo_addr_a : line_addr_a];
        rd_1_b <= line_1[geometry_a ? geo_addr_a : line_addr_a];
        rd_2_b <= line_2[geometry_a && geometry_flip ? geo_addr_a : line_addr_a];
        geometry_b<=geometry_a;geo_pair_b<=geo_pair_a;geo_shape_b<=geo_shape_a;geo_flip_b<=geo_flip_a;geo_inside_b<=geo_inside_a;
        rb_top_b <= rb_top_a;
        rb_bot_b <= rb_bot_a;
    end

    // stage B2 — 选块 mux 单独打一拍（这一级就是被 -5.181 ns 逼出来的：
    //            选块 mux 与后面的加法树串在一起时，整锥跑了 ~18.5 ns）
    always @(posedge clk) begin
        d_top_r     <= geometry_b && geo_flip_b && !geo_inside_b ? 24'd0 : d_top;
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

// A-only, read-only geometry over immutable RGB888 cache slots. No new memory
// controller, write command, network packet or clock domain is introduced.
module geometry_row_reader(
 input clk,rst,active,frame_start,line_start,
 input [9:0] output_y,next_old_y,input flip,
 input [11:0] width,input [9:0] height,top,input [16:0] inv_y,
 input [20:0] old_base,new_base,input back_half,old_rgb444,new_rgb444,output reg read_rgb444,
 output reg read_req, input read_ack,output reg read_en,input read_empty,
 output reg [20:0] read_base,output write_enable,output [1:0] write_bank,output [9:0] write_addr,
 output background_valid,foreground_valid,output [1:0] display_pair);
 localparam IDLE=0,CALC=1,ADDRESS=2,REQUEST=3,WAIT_FIFO=4,ISSUE=5,Y_PRODUCT=6;
 reg [2:0] state;
 reg active_d,pair,foreground;
 reg [9:0] target_y,target_old_y,issued,received;
 reg [5:0] wait_count;
 reg read_en_d,empty_d;
 reg [26:0] y_product;
 reg [9:0] y_delta;
 wire [14:0] foreground_y=y_product[26:12];
 wire zoom_row=height!=0 && target_y>=top && {1'b0,target_y}<{1'b0,top}+height;
 reg [9:0] tag0,tag1;reg bg0,bg1,fg0,fg1;
 reg line_bg,line_fg;
 wire tag_matches=output_y[0]?tag1==output_y:tag0==output_y;
 wire row_bg=tag_matches && (output_y[0]?bg1:bg0);
 wire row_fg=tag_matches && (output_y[0]?fg1:fg0);
 assign background_valid=line_start?row_bg:line_bg;
 assign foreground_valid=line_start?row_fg:line_fg;
 assign display_pair={1'b0,output_y[0]};
 assign write_enable=active && state==ISSUE && read_en_d && !empty_d && received<640;
 assign write_bank={pair,foreground};assign write_addr=received;
 wire pop=read_en && !read_empty;
 function [20:0] row_offset;input [9:0] sy;input compact;reg [20:0] full_offset;
 begin full_offset=({11'd0,sy}<<9)-({11'd0,sy}<<5);row_offset=compact?full_offset>>1:full_offset;end endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;active_d<=0;read_req<=0;read_en<=0;read_en_d<=0;empty_d<=1;
   pair<=0;foreground<=0;target_y<=0;target_old_y<=0;issued<=0;received<=0;wait_count<=0;
   read_base<=0;read_rgb444<=0;y_product<=0;y_delta<=0;tag0<=1023;tag1<=1023;bg0<=0;bg1<=0;fg0<=0;fg1<=0;line_bg<=0;line_fg<=0;
  end else begin
   active_d<=active;read_en<=0;read_en_d<=read_en;empty_d<=read_empty;
   if(line_start)begin line_bg<=row_bg;line_fg<=row_fg;end
   if(!active)begin state<=IDLE;read_req<=0;read_en<=0;bg0<=0;bg1<=0;fg0<=0;fg1<=0;line_bg<=0;line_fg<=0;end
   else if(frame_start || !active_d)begin
    state<=CALC;read_req<=0;read_en<=0;read_en_d<=0;empty_d<=1;
    pair<=0;foreground<=0;target_y<=0;target_old_y<=0;
    tag0<=1023;tag1<=1023;bg0<=0;bg1<=0;fg0<=0;fg1<=0;line_bg<=0;line_fg<=0;
   end else case(state)
    IDLE:if(line_start && output_y<719)begin
     target_y<=output_y+1'b1;target_old_y<=next_old_y;pair<=!output_y[0];foreground<=0;state<=CALC;
    end
    CALC:begin
     y_delta<=target_y>=top?target_y-top:10'd0;
     if(pair)begin tag1<=target_y;bg1<=0;fg1<=0;end else begin tag0<=target_y;bg0<=0;fg0<=0;end
     state<=Y_PRODUCT;
    end
    Y_PRODUCT:begin y_product<=y_delta*inv_y;state<=ADDRESS;end
    ADDRESS:begin
     if(flip && width==0)begin
      if(pair)bg1<=1;else bg0<=1;state<=IDLE;
     end else begin
      read_rgb444<=flip && back_half?new_rgb444:old_rgb444;
      read_base<=(flip && back_half?new_base:old_base)+row_offset(target_old_y,flip && back_half?new_rgb444:old_rgb444);state<=REQUEST;
     end
    end
    REQUEST:begin
     read_req<=1;
     if(read_req && read_ack)begin read_req<=0;wait_count<=48;read_en_d<=0;state<=WAIT_FIFO;end
    end
    WAIT_FIFO:if(wait_count!=0)wait_count<=wait_count-1'b1;
     else begin issued<=0;received<=0;read_en<=!read_empty;read_en_d<=0;state<=ISSUE;end
    ISSUE:begin
     if(read_en_d && !empty_d)received<=received+1'b1;
     if(pop)issued<=issued+1'b1;
     if(received==640)begin
      read_en<=0;
      if(!foreground && !flip && zoom_row)begin
       if(pair)bg1<=1;else bg0<=1;
       foreground<=1;
       read_rgb444<=new_rgb444;
       read_base<=new_base+row_offset(foreground_y>=480?10'd479:foreground_y[9:0],new_rgb444);
       read_en_d<=0;state<=REQUEST;
      end else begin
       if(pair)begin bg1<=1;if(foreground)fg1<=1;end
       else begin bg0<=1;if(foreground)fg0<=1;end
       state<=IDLE;
      end
     end else if(issued+(pop?10'd1:10'd0)<640)read_en<=!read_empty;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule

module photo_geometry_control #(parameter integer PHASE_STEP=1,SLOT_BITS=3,DYNAMIC_SLOTS=0)(
 input clk,rst,frame_start,eligible,input [2:0] selector,
 input [SLOT_BITS-1:0] slot_in,input commit_toggle,
 output reg active,output reg flip,output reg [5:0] phase,
 output reg [SLOT_BITS-1:0] old_slot,new_slot,
 output reg [11:0] width,output reg [9:0] height,
 output [11:0] left,output [9:0] top,
 output reg [16:0] inv_x,inv_y,output back_half,
 output [SLOT_BITS-1:0] idle_slot,output hold_slot);
 reg [2:0] toggle_sync;reg [SLOT_BITS-1:0] held_slot,last_slot;reg armed;
 localparam [5:0] PHASE_INC=PHASE_STEP;
 wire event_seen=toggle_sync[2]!=toggle_sync[1];
 wire selected=selector==1 || selector==2;
 assign idle_slot=last_slot;
 assign hold_slot=armed && eligible && selected;
 wire [5:0] scale=flip?(phase<16?6'd32-{phase[4:0],1'b0}:{phase[4:0],1'b0}-6'd32):phase;
 assign left=(12'd1280-width)>>1;assign top=(10'd720-height)>>1;
 assign back_half=phase>=16;
 always @(posedge clk or posedge rst)begin
  if(rst)begin toggle_sync<=0;held_slot<=2;last_slot<=2;armed<=0;active<=0;flip<=0;phase<=0;old_slot<=2;new_slot<=2;end
  else begin
   toggle_sync<={toggle_sync[1:0],commit_toggle};
   if(event_seen)held_slot<=slot_in;
   if(frame_start)begin
    if(!eligible || !selected)begin active<=0;armed<=0;last_slot<=held_slot;phase<=0;end
    else if(!armed)begin armed<=1;last_slot<=held_slot;active<=0;end
    else if(active)begin
     if(phase==32)begin active<=0;last_slot<=new_slot;end else phase<=phase+PHASE_INC;
    end else if(DYNAMIC_SLOTS && held_slot[SLOT_BITS-1] && last_slot[SLOT_BITS-1])begin
     // Successive live particle buffers are motion, not a new slideshow
     // page. Track their complete slot without restarting an effect.
     last_slot<=held_slot;
    end else if(held_slot!=last_slot)begin
     old_slot<=last_slot;new_slot<=held_slot;flip<=selector==1;phase<=0;active<=1;
    end
   end
  end
 end
 reg [11:0] width_c;reg [9:0] height_c;reg [16:0] inv_x_c,inv_y_c;
 always @(posedge clk or posedge rst)
  if(rst)begin width<=0;height<=0;inv_x<=0;inv_y<=0;end
  else begin width<=width_c;height<=height_c;inv_x<=inv_x_c;inv_y<=inv_y_c;end
 // Constant reciprocal ROM, Q12; no variable divider or perspective engine.
 always @* begin
  width_c=0;height_c=0;inv_x_c=0;inv_y_c=0;
  case(scale)
   6'd0:begin width_c=12'd0;height_c=10'd0;inv_x_c=17'd0;inv_y_c=17'd0;end
   6'd1:begin width_c=12'd40;height_c=10'd22;inv_x_c=17'd65536;inv_y_c=17'd89367;end
   6'd2:begin width_c=12'd80;height_c=10'd45;inv_x_c=17'd32768;inv_y_c=17'd43690;end
   6'd3:begin width_c=12'd120;height_c=10'd67;inv_x_c=17'd21845;inv_y_c=17'd29344;end
   6'd4:begin width_c=12'd160;height_c=10'd90;inv_x_c=17'd16384;inv_y_c=17'd21845;end
   6'd5:begin width_c=12'd200;height_c=10'd112;inv_x_c=17'd13107;inv_y_c=17'd17554;end
   6'd6:begin width_c=12'd240;height_c=10'd135;inv_x_c=17'd10922;inv_y_c=17'd14563;end
   6'd7:begin width_c=12'd280;height_c=10'd157;inv_x_c=17'd9362;inv_y_c=17'd12522;end
   6'd8:begin width_c=12'd320;height_c=10'd180;inv_x_c=17'd8192;inv_y_c=17'd10922;end
   6'd9:begin width_c=12'd360;height_c=10'd202;inv_x_c=17'd7281;inv_y_c=17'd9733;end
   6'd10:begin width_c=12'd400;height_c=10'd225;inv_x_c=17'd6553;inv_y_c=17'd8738;end
   6'd11:begin width_c=12'd440;height_c=10'd247;inv_x_c=17'd5957;inv_y_c=17'd7959;end
   6'd12:begin width_c=12'd480;height_c=10'd270;inv_x_c=17'd5461;inv_y_c=17'd7281;end
   6'd13:begin width_c=12'd520;height_c=10'd292;inv_x_c=17'd5041;inv_y_c=17'd6733;end
   6'd14:begin width_c=12'd560;height_c=10'd315;inv_x_c=17'd4681;inv_y_c=17'd6241;end
   6'd15:begin width_c=12'd600;height_c=10'd337;inv_x_c=17'd4369;inv_y_c=17'd5834;end
   6'd16:begin width_c=12'd640;height_c=10'd360;inv_x_c=17'd4096;inv_y_c=17'd5461;end
   6'd17:begin width_c=12'd680;height_c=10'd382;inv_x_c=17'd3855;inv_y_c=17'd5146;end
   6'd18:begin width_c=12'd720;height_c=10'd405;inv_x_c=17'd3640;inv_y_c=17'd4854;end
   6'd19:begin width_c=12'd760;height_c=10'd427;inv_x_c=17'd3449;inv_y_c=17'd4604;end
   6'd20:begin width_c=12'd800;height_c=10'd450;inv_x_c=17'd3276;inv_y_c=17'd4369;end
   6'd21:begin width_c=12'd840;height_c=10'd472;inv_x_c=17'd3120;inv_y_c=17'd4165;end
   6'd22:begin width_c=12'd880;height_c=10'd495;inv_x_c=17'd2978;inv_y_c=17'd3971;end
   6'd23:begin width_c=12'd920;height_c=10'd517;inv_x_c=17'd2849;inv_y_c=17'd3802;end
   6'd24:begin width_c=12'd960;height_c=10'd540;inv_x_c=17'd2730;inv_y_c=17'd3640;end
   6'd25:begin width_c=12'd1000;height_c=10'd562;inv_x_c=17'd2621;inv_y_c=17'd3498;end
   6'd26:begin width_c=12'd1040;height_c=10'd585;inv_x_c=17'd2520;inv_y_c=17'd3360;end
   6'd27:begin width_c=12'd1080;height_c=10'd607;inv_x_c=17'd2427;inv_y_c=17'd3239;end
   6'd28:begin width_c=12'd1120;height_c=10'd630;inv_x_c=17'd2340;inv_y_c=17'd3120;end
   6'd29:begin width_c=12'd1160;height_c=10'd652;inv_x_c=17'd2259;inv_y_c=17'd3015;end
   6'd30:begin width_c=12'd1200;height_c=10'd675;inv_x_c=17'd2184;inv_y_c=17'd2912;end
   6'd31:begin width_c=12'd1240;height_c=10'd697;inv_x_c=17'd2114;inv_y_c=17'd2820;end
   6'd32:begin width_c=12'd1280;height_c=10'd720;inv_x_c=17'd2048;inv_y_c=17'd2730;end
  default:begin width_c=1280;height_c=720;inv_x_c=2048;inv_y_c=2730;end
  endcase
 end
endmodule
