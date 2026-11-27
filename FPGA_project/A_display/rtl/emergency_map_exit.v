`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// emergency_map_exit -- 安全出口（EXIT 标志）
//
// 四道门各画一个"EXIT 灯箱"：深绿底 + 亮绿描边 + 箱内亮绿 EXIT 三像素字模。
//   推荐出口那一道额外套一圈会呼吸的外框（blink_on 在两个绿之间切换），
//   于是"该走哪个门"在 3 秒内一眼可见 —— 对应需求"安全出口明显/呼吸高亮"。
//
// 为什么用 3x5 点阵而不是调 emergency_map_glyphs：那块 ROM 的字是 16 px 高，
//   四个字母就要 64 px 宽，塞不进灯箱；3x5 只要 16x5，正好落在灯箱里。
//
// ★ 两级流水（本次时序整改）：第 1 级把"在哪只灯箱里 / 描边 / 字模点亮 /
//   推荐门 / 呼吸外框"全部判成标志并寄存，第 2 级只做选色。
//
// 位置与设计稿 gen_evac_guide（448x189 设计空间）按百分比对齐：
//   东门 (95%,22%) 西门 (1%,77%) 北门/南门 (48%,1% / 48%,93%)
// ---------------------------------------------------------------------------
module emergency_map_exit #(
    parameter integer SCREEN_W = 1280,
    parameter integer SCREEN_H = 720,
    parameter integer MAP_XP0  = 26,
    parameter integer MAP_XP1  = 74,
    parameter integer MAP_YP0  = 43,
    parameter integer MAP_YP1  = 79
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [11:0] lx, ly,
    input  wire        blink_on,     // 呼吸相位
    input  wire [1:0]  rec_exit,     // 0 东门 1 西门 2 南门 3 集合点(操场)

    output reg  [23:0] ex_rgb,
    output reg  [7:0]  ex_alpha
);

    // WW/WH 必须与 emergency_map_top 的窗口完全一致（947-332=615 / 568-309=259）。
    // 用"先整除再相减"而不是"(XP1-XP0) 乘宽度再除"，否则会差 1 px。
    localparam [11:0] WW = (SCREEN_W*MAP_XP1/100) - (SCREEN_W*MAP_XP0/100);   // 615
    localparam [11:0] WH = (SCREEN_H*MAP_YP1/100) - (SCREEN_H*MAP_YP0/100);   // 259

    localparam [23:0] C_BOX_D  = 24'h0E3A24;   // 灯箱底（深绿）
    localparam [23:0] C_BOX_B  = 24'h4FD08A;   // 灯箱边 + EXIT 字（亮绿）
    localparam [23:0] C_ON_D   = 24'h1E7A4C;   // 推荐门灯箱底（亮一点）
    localparam [23:0] C_ON_B   = 24'hC8FFDE;   // 推荐门灯箱边（近白绿）
    localparam [23:0] C_GLOW_A = 24'h2E8A58;   // 呼吸外框 · 亮相
    localparam [23:0] C_GLOW_B = 24'h14512F;   // 呼吸外框 · 暗相

    localparam [11:0] BW = 12'd30;             // 灯箱宽
    localparam [11:0] BH = 12'd16;             // 灯箱高

    // ---- 四个灯箱的左上角 ----
    localparam [11:0] EX = WW*95/100;  localparam [11:0] EY = WH*22/100;   // 584, 56
    localparam [11:0] WX = WW*1/100;   localparam [11:0] WY = WH*77/100;   // 6,  199
    localparam [11:0] NX = WW*48/100;  localparam [11:0] NY = WH*1/100;    // 295, 2
    localparam [11:0] SX = WW*48/100;  localparam [11:0] SY = WH*93/100;   // 295, 240
    wire on_e = (lx >= EX) && (lx < (EX + BW)) && (ly >= EY) && (ly < (EY + BH));
    wire on_w = (lx >= WX) && (lx < (WX + BW)) && (ly >= WY) && (ly < (WY + BH));
    wire on_n = (lx >= NX) && (lx < (NX + BW)) && (ly >= NY) && (ly < (NY + BH));
    wire on_s = (lx >= SX) && (lx < (SX + BW)) && (ly >= SY) && (ly < (SY + BH));
    wire in_box = on_e || on_w || on_n || on_s;

    // 推荐门（rec_exit 0/1/2 对应东/西/南门；3=集合点，四道门都不算推荐门）
    wire rec_e = (rec_exit == 2'd0);
    wire rec_w = (rec_exit == 2'd1);
    wire rec_s = (rec_exit == 2'd2);
    wire rec_n = 1'b0;
    wire is_rec = (on_e && rec_e) || (on_w && rec_w) || (on_s && rec_s) || (on_n && rec_n);

    // 呼吸外框：推荐门灯箱外 2 px 的一圈
    wire ring_e = rec_e && (lx >= (EX - 12'd2)) && (lx < (EX + BW + 12'd2)) &&
                            (ly >= (EY - 12'd2)) && (ly < (EY + BH + 12'd2));
    wire ring_w = rec_w && (lx >= (WX - 12'd2)) && (lx < (WX + BW + 12'd2)) &&
                            (ly >= (WY - 12'd2)) && (ly < (WY + BH + 12'd2));
    wire ring_n = rec_n && (lx >= (NX - 12'd2)) && (lx < (NX + BW + 12'd2)) &&
                            (ly >= (NY - 12'd2)) && (ly < (NY + BH + 12'd2));
    wire ring_s = rec_s && (lx >= (SX - 12'd2)) && (lx < (SX + BW + 12'd2)) &&
                            (ly >= (SY - 12'd2)) && (ly < (SY + BH + 12'd2));
    wire in_ring = (ring_e || ring_w || ring_n || ring_s) && !in_box;

    // ---- 灯箱内坐标 ----
    wire [11:0] bx = on_e ? (lx - EX) : on_w ? (lx - WX) : on_n ? (lx - NX) : (lx - SX);
    wire [11:0] by = on_e ? (ly - EY) : on_w ? (ly - WY) : on_n ? (ly - NY) : (ly - SY);

    wire on_border = (bx == 12'd0) || (bx == (BW - 12'd1)) ||
                     (by == 12'd0) || (by == (BH - 12'd1));

    // EXIT 三像素字模：4 个字母 x 5 行，字格 4 px（3 px 笔画 + 1 px 间隔）
    // 字块左上角放在灯箱内 (7,5)，共 16x5
    wire [11:0] gxo = bx - 12'd7;
    wire [11:0] gyo = by - 12'd5;
    wire in_glyph = (bx >= 12'd7) && (bx < 12'd23) && (by >= 12'd5) && (by < 12'd10);
    wire [1:0]  gci = gxo[3:2];       // 0..3 -> E X I T
    wire [2:0]  gcl = gxo[1:0];       // 字内列
    wire [2:0]  gcr = gyo[2:0];       // 字内行

    // 行码：{第0列, 第1列, 第2列, 1'b0}；查表时用 (3 - 列号) 取位，
    // 列号 3 落在恒 0 的第 0 位上 —— 于是"间隔列"自然不打点，也不会有越界索引。
    reg [3:0] grow;
    always @(*) begin
        case ({gci, gcr})
            {2'd0, 3'd0}: grow = 4'b1110;   {2'd0, 3'd1}: grow = 4'b1000;
            {2'd0, 3'd2}: grow = 4'b1100;   {2'd0, 3'd3}: grow = 4'b1000;
            {2'd0, 3'd4}: grow = 4'b1110;
            {2'd1, 3'd0}: grow = 4'b1010;   {2'd1, 3'd1}: grow = 4'b1010;
            {2'd1, 3'd2}: grow = 4'b0100;   {2'd1, 3'd3}: grow = 4'b1010;
            {2'd1, 3'd4}: grow = 4'b1010;
            {2'd2, 3'd0}: grow = 4'b1110;   {2'd2, 3'd1}: grow = 4'b0100;
            {2'd2, 3'd2}: grow = 4'b0100;   {2'd2, 3'd3}: grow = 4'b0100;
            {2'd2, 3'd4}: grow = 4'b1110;
            default: begin  // T
                if (gcr == 3'd0)      grow = 4'b1110;
                else                  grow = 4'b0100;
            end
        endcase
    end

    wire lit_n = in_glyph && grow[2'd3 - gcl];

    // ==================================================================
    // R2：全部判成标志（只依赖 lx/ly 与 plan 的寄存器）
    // ==================================================================
    reg f_box, f_rec, f_ring, f_border, f_lit;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            f_box <= 1'b0; f_rec <= 1'b0; f_ring <= 1'b0; f_border <= 1'b0; f_lit <= 1'b0;
        end
        else begin
            f_box    <= in_box;
            f_rec    <= is_rec;
            f_ring   <= in_ring;
            f_border <= on_border;
            f_lit    <= lit_n;
        end
    end

    // ==================================================================
    // R3：类别码（只依赖 R2 标志）
    //   0=无 1=呼吸外框 2/3=非推荐/推荐门描边 4/5=非推荐/推荐门 EXIT 字
    //   6/7=非推荐/推荐门灯箱底
    // ==================================================================
    wire [2:0] cls_n = !f_box ? (f_ring ? 3'd1 : 3'd0) :
                       f_border ? (f_rec ? 3'd3 : 3'd2) :
                       f_lit    ? (f_rec ? 3'd5 : 3'd4) :
                                  (f_rec ? 3'd7 : 3'd6);

    reg [2:0] r3_cls;
    always @(posedge clk or posedge rst) begin
        if (rst) r3_cls <= 3'd0;
        else     r3_cls <= cls_n;
    end

    // ==================================================================
    // R4：选色
    // ==================================================================
    reg [23:0] r4_rgb;
    reg [7:0]  r4_a;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r4_rgb <= 24'd0; r4_a <= 8'd0;
        end
        else begin
            case (r3_cls)
                3'd1:    begin r4_rgb <= blink_on ? C_GLOW_A : C_GLOW_B; r4_a <= 8'd255; end
                3'd2:    begin r4_rgb <= C_BOX_B; r4_a <= 8'd255; end
                3'd3:    begin r4_rgb <= C_ON_B;  r4_a <= 8'd255; end
                3'd4:    begin r4_rgb <= C_BOX_B; r4_a <= 8'd255; end
                3'd5:    begin r4_rgb <= 24'hFFFFFF; r4_a <= 8'd255; end
                3'd6:    begin r4_rgb <= C_BOX_D; r4_a <= 8'd255; end
                3'd7:    begin r4_rgb <= C_ON_D;  r4_a <= 8'd255; end
                default: begin r4_rgb <= 24'd0;   r4_a <= 8'd0;   end
            endcase
        end
    end

    // ==================================================================
    // R5：输出寄存器
    // ==================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ex_rgb   <= 24'd0;
            ex_alpha <= 8'd0;
        end
        else begin
            ex_rgb   <= r4_rgb;
            ex_alpha <= r4_a;
        end
    end

endmodule
