`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// emergency_map_text -- 地图上的中文标注（建筑名 / 危险区域 / 出口名 / 当前位置…）
//
// 为什么值得单独做一个模块：设计稿上一半的“显得专业”来自标注 —— 8 栋楼有名字、
//   危险区有红底白字角标、推荐出口写着“推荐出口 东门”。没有这些，再漂亮的矩形
//   也只是色块。FPGA 上做到这件事只需要两块小 ROM：
//     emergency_map_glyphs : 16x16 点阵字模（64 字，约 256 个 LUT6）
//     本模块的字符索引表    : 22 条标注 x 8 字 x 6 bit（约 25 个 LUT6）
//
// 像素级算法（每字 16 px 定宽，正好用移位代替除法）：
//     cpos = (lx - bx) >> 4      第几个字
//     col  = (lx - bx) & 4'hF    字内第几列
//     row  =  ly - by            字内第几行
//     lit  = glyph[char[lid][cpos]][row] >> (15 - col)
//
// ★ 流水（统一 4 级内部寄存 R2..R5，本模块吃 top 的 R1 窗口局部坐标）：
//     R2：22 条标注的命中判定 + 编号归约 + 角标红底判定（本模块最长的一段）
//     R3：标注基址 -> 字内坐标 -> 字符索引表
//     R4：字形 ROM（16x16 点阵）
//     R5：位选 + 选色 + 角标红底覆盖
//   改造前“命中判定 + 编号 + 字符索引”挤在一拍，实测 18 级逻辑、22.2 ns，
//   是全设计最差路径；拆成 4 段后最长一段约 8 级。
// ---------------------------------------------------------------------------
module emergency_map_text #(
    parameter integer SCREEN_W = 1280,
    parameter integer SCREEN_H = 720,
    parameter integer MAP_XP0  = 26,
    parameter integer MAP_XP1  = 74,
    parameter integer MAP_YP0  = 43,
    parameter integer MAP_YP1  = 79
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,        // 0 = 不画任何文字（窗口/非应急）

    input  wire [11:0] px, py,        // R1 级窗口局部坐标（top 的 R1 寄存器输出）

    input  wire [1:0]  event_type,
    input  wire [1:0]  rec_exit,
    input  wire        d0_en, d1_en,
    input  wire [11:0] d0_x0, d0_y0,
    input  wire [11:0] acc_x, acc_y,
    input  wire [11:0] per_x, per_y,

    output reg  [23:0] txt_rgb,
    output reg  [7:0]  txt_alpha
);

    // WW/WH 必须与 emergency_map_top 的**设计坐标空间**完全一致（640x360）。
    // top 是"全屏 + 2 倍放大"：它把 DW/DH（= SCREEN/2）传给本模块。
    // 用“先整除再相减”而不是“(XP1-XP0) 乘宽度再除”，否则会差 1 px。
    localparam [11:0] WW = (SCREEN_W*MAP_XP1/100) - (SCREEN_W*MAP_XP0/100);
    localparam [11:0] WH = (SCREEN_H*MAP_YP1/100) - (SCREEN_H*MAP_YP0/100);

    localparam [11:0] OVX = WW*50/100;
    localparam [11:0] OVY = WH*40/100;
    localparam [11:0] FOOT_Y = WH - 12'd19;   // 页脚基线 240

    // ==================================================================
    // R2 组合：命中判定
    //   标注编号（与基址表必须一致）
    //     0..7   八栋建筑名
    //     8..11  事件相关角标：危险区域 / 事故位置 / 集合点 / 推荐出口
    //     12..15 四个门名
    //     16     当前位置
    //     17     页脚标题
    //     18..21 页脚事件名（四选一）
    // ==================================================================
    wire in_dgr = d0_en || d1_en;

    // 推荐出口角标的位置随推荐出口走（组合，供 lhit/基址表用）
    wire [11:0] recx = (rec_exit == 2'd0) ? WW*82/100 :
                       (rec_exit == 2'd1) ? WW*1/100  :
                       (rec_exit == 2'd2) ? WW*52/100 : (OVX - 12'd32);
    wire [11:0] recy = (rec_exit == 2'd0) ? WH*28/100 :
                       (rec_exit == 2'd1) ? WH*88/100 :
                       (rec_exit == 2'd2) ? WH*86/100 : (OVY + 12'd22);

    wire [21:0] lhit;
    //   八栋楼名（lid 0..7）：横竖都"居中于本楼"，直接由 base.v 的同一套百分比推出。
    //   设计空间 640x360：列 [BX0=19,COLW=134,CGAP=25] 的中心 = 86/245/404/563；
    //   两排建筑 [TOPY=18,ROWH=61] / [BOTY=212,ROWH=61] 的中心 = 48 / 242。
    //   框宽 = 字宽（16 px）x 字数：5 字 80、3 字 48、2 字 32。
    assign lhit[0]  = !in_dgr && (px >= 12'd46)  && (px < 12'd126) && (py >= 12'd40)  && (py < 12'd56);
    assign lhit[1]  = !in_dgr && (px >= 12'd221) && (px < 12'd269) && (py >= 12'd40)  && (py < 12'd56);
    assign lhit[2]  = !in_dgr && (px >= 12'd380) && (px < 12'd428) && (py >= 12'd40)  && (py < 12'd56);
    assign lhit[3]  = !in_dgr && (px >= 12'd539) && (px < 12'd587) && (py >= 12'd40)  && (py < 12'd56);
    assign lhit[4]  = !in_dgr && (px >= 12'd62)  && (px < 12'd110) && (py >= 12'd234) && (py < 12'd250);
    assign lhit[5]  = !in_dgr && (px >= 12'd205) && (px < 12'd285) && (py >= 12'd234) && (py < 12'd250);
    assign lhit[6]  = !in_dgr && (px >= 12'd380) && (px < 12'd428) && (py >= 12'd234) && (py < 12'd250);
    assign lhit[7]  = !in_dgr && (px >= 12'd547) && (px < 12'd579) && (py >= 12'd234) && (py < 12'd250);
    assign lhit[8]  = d0_en && (px >= (d0_x0 + 12'd4))  && (px < (d0_x0 + 12'd70)) && (py >= (d0_y0 + 12'd3)) && (py < (d0_y0 + 12'd21));
    assign lhit[9]  = d0_en && (px >= (acc_x + 12'd8))  && (px < (acc_x + 12'd72)) && (py >= acc_y) && (py < (acc_y + 12'd18));
    assign lhit[10] = (px >= (OVX - 12'd42)) && (px < (OVX + 12'd38)) && (py >= (OVY + 12'd4)) && (py < (OVY + 12'd20));
    assign lhit[11] = (px >= recx) && (px < (recx + 12'd64)) && (py >= recy) && (py < (recy + 12'd16));
    assign lhit[12] = (px >= (WW*93/100))       && (px < (WW*93/100 + 12'd32)) && (py >= (WH*28/100)) && (py < (WH*28/100 + 12'd16));
    assign lhit[13] = (px >= (WW*1/100))        && (px < (WW*1/100 + 12'd32))  && (py >= (WH*81/100)) && (py < (WH*81/100 + 12'd16));
    assign lhit[14] = (px >= (WW*53/100))       && (px < (WW*53/100 + 12'd32)) && (py >= (WH*93/100)) && (py < (WH*93/100 + 12'd16));
    assign lhit[15] = (px >= (WW*53/100))       && (px < (WW*53/100 + 12'd32)) && (py >= (WH*1/100))  && (py < (WH*1/100 + 12'd16));
    assign lhit[16] = (px >= (per_x - 12'd32)) && (px < (per_x + 12'd32)) && (py >= (per_y - 12'd32)) && (py < (per_y - 12'd16));
    assign lhit[17] = (px >= (WW*65/100))       && (px < (WW*65/100 + 12'd112)) && (py >= FOOT_Y) && (py < (FOOT_Y + 12'd16));
    assign lhit[18] = (event_type == 2'd0) && (px >= (WW - 12'd40)) && (px < (WW - 12'd8)) && (py >= FOOT_Y) && (py < (FOOT_Y + 12'd16));
    assign lhit[19] = (event_type == 2'd1) && (px >= (WW - 12'd40)) && (px < (WW - 12'd8)) && (py >= FOOT_Y) && (py < (FOOT_Y + 12'd16));
    assign lhit[20] = (event_type == 2'd2) && (px >= (WW - 12'd88)) && (px < (WW - 12'd8)) && (py >= FOOT_Y) && (py < (FOOT_Y + 12'd16));
    assign lhit[21] = (event_type == 2'd3) && (px >= (WW - 12'd40)) && (px < (WW - 12'd8)) && (py >= FOOT_Y) && (py < (FOOT_Y + 12'd16));

    // 一位热码 -> 5 bit 标号（无优先级链，纯 OR 归约，约 3 级）
    wire [4:0] lid;
    assign lid[4] = |lhit[21:16];
    assign lid[3] = |lhit[15:8];
    assign lid[2] = |lhit[7:4] | |lhit[15:12] | |lhit[21:20];
    assign lid[1] = |lhit[3:2] | |lhit[7:6] | |lhit[11:10] | |lhit[15:14] | |lhit[19:18];
    assign lid[0] = |{lhit[1],lhit[3],lhit[5],lhit[7],lhit[9],lhit[11],
                      lhit[13],lhit[15],lhit[17],lhit[19],lhit[21]};
    wire any_hit = |lhit;

    // 危险区角标底：覆盖“危险区域”四个字 + 内边距（基址取 lid==8 的那一项）
    wire [11:0] bx8 = d0_x0 + 12'd6;
    wire [11:0] by8 = d0_y0 + 12'd5;
    wire badge_box = (lid == 5'd8) && (px >= (bx8 - 12'd3)) && (px < (bx8 + 12'd67)) &&
                     (py >= (by8 - 12'd3)) && (py < (by8 + 12'd19));

    reg        r2_val, r2_badge;
    reg [4:0]  r2_lid;
    reg [11:0] r2_lx, r2_ly;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r2_val <= 1'b0; r2_badge <= 1'b0; r2_lid <= 5'd0;
            r2_lx <= 12'd0; r2_ly <= 12'd0;
        end
        else begin
            r2_val   <= enable && any_hit;
            r2_badge <= enable && badge_box;
            r2_lid   <= lid;
            r2_lx    <= px;
            r2_ly    <= py;
        end
    end

    // ==================================================================
    // R3 组合：基址 -> 字内坐标 -> 字符索引（只依赖 R2 寄存器）
    // ==================================================================
    reg [11:0] bx, by;
    always @(*) begin
        case (r2_lid)
            5'd0:  begin bx = 12'd46;  by = 12'd40;  end
            5'd1:  begin bx = 12'd221; by = 12'd40;  end
            5'd2:  begin bx = 12'd380; by = 12'd40;  end
            5'd3:  begin bx = 12'd539; by = 12'd40;  end
            5'd4:  begin bx = 12'd62;  by = 12'd234; end
            5'd5:  begin bx = 12'd205; by = 12'd234; end
            5'd6:  begin bx = 12'd380; by = 12'd234; end
            5'd7:  begin bx = 12'd547; by = 12'd234; end
            5'd8:  begin bx = d0_x0 + 12'd6;  by = d0_y0 + 12'd5;  end
            5'd9:  begin bx = acc_x + 12'd10; by = acc_y + 12'd2;  end
            5'd10: begin bx = OVX - 12'd40;   by = OVY + 12'd6;    end
            5'd11: begin bx = recx;           by = recy;           end
            5'd12: begin bx = WW*93/100;      by = WH*28/100;      end
            5'd13: begin bx = WW*1/100;       by = WH*81/100;      end
            5'd14: begin bx = WW*53/100;      by = WH*93/100;      end
            5'd15: begin bx = WW*53/100;      by = WH*1/100;       end
            5'd16: begin bx = per_x - 12'd32; by = per_y - 12'd30; end
            5'd17: begin bx = WW*65/100;      by = FOOT_Y;         end
            5'd18: begin bx = WW - 12'd40;    by = FOOT_Y;         end
            5'd19: begin bx = WW - 12'd40;    by = FOOT_Y;         end
            5'd20: begin bx = WW - 12'd88;    by = FOOT_Y;         end
            default: begin bx = WW - 12'd40;  by = FOOT_Y;         end
        endcase
    end

    wire [11:0] tx = r2_lx - bx;
    wire [11:0] ty = r2_ly - by;
    wire [2:0]  cpos = tx[6:4];

    // 字符索引表：22 条标注 x 8 字（字形索引见 emergency_map_glyphs.v 表头）
    reg [5:0] chr;
    always @(*) begin
        case ({r2_lid, cpos})
            // 教学楼A区
            {5'd0,3'd0}: chr = 6'd0;  {5'd0,3'd2}: chr = 6'd2;  {5'd0,3'd4}: chr = 6'd3;
            {5'd0,3'd1}: chr = 6'd1;  {5'd0,3'd3}: chr = 6'd55;
            // 图书馆
            {5'd1,3'd0}: chr = 6'd4;  {5'd1,3'd1}: chr = 6'd5;  {5'd1,3'd2}: chr = 6'd6;
            // 行政楼
            {5'd2,3'd0}: chr = 6'd7;  {5'd2,3'd1}: chr = 6'd8;  {5'd2,3'd2}: chr = 6'd2;
            // 体育馆
            {5'd3,3'd0}: chr = 6'd9;  {5'd3,3'd1}: chr = 6'd10; {5'd3,3'd2}: chr = 6'd6;
            // 实验楼
            {5'd4,3'd0}: chr = 6'd11; {5'd4,3'd1}: chr = 6'd12; {5'd4,3'd2}: chr = 6'd2;
            // 教学楼B区
            {5'd5,3'd0}: chr = 6'd0;  {5'd5,3'd2}: chr = 6'd2;  {5'd5,3'd4}: chr = 6'd3;
            {5'd5,3'd1}: chr = 6'd1;  {5'd5,3'd3}: chr = 6'd56;
            // 宿舍区 / 食堂
            {5'd6,3'd0}: chr = 6'd13; {5'd6,3'd1}: chr = 6'd14; {5'd6,3'd2}: chr = 6'd3;
            {5'd7,3'd0}: chr = 6'd15; {5'd7,3'd1}: chr = 6'd16;
            // 危险区域
            {5'd8,3'd0}: chr = 6'd17; {5'd8,3'd1}: chr = 6'd18; {5'd8,3'd2}: chr = 6'd3;  {5'd8,3'd3}: chr = 6'd19;
            // 事故位置
            {5'd9,3'd0}: chr = 6'd20; {5'd9,3'd1}: chr = 6'd21; {5'd9,3'd2}: chr = 6'd22; {5'd9,3'd3}: chr = 6'd23;
            // 集合点操场
            {5'd10,3'd0}: chr = 6'd24; {5'd10,3'd1}: chr = 6'd25; {5'd10,3'd2}: chr = 6'd26;
            {5'd10,3'd3}: chr = 6'd27; {5'd10,3'd4}: chr = 6'd28;
            // 推荐出口
            {5'd11,3'd0}: chr = 6'd29; {5'd11,3'd1}: chr = 6'd30; {5'd11,3'd2}: chr = 6'd31; {5'd11,3'd3}: chr = 6'd62;
            // 东门 / 西门 / 南门 / 北门
            {5'd12,3'd0}: chr = 6'd32; {5'd13,3'd0}: chr = 6'd33; {5'd14,3'd0}: chr = 6'd34; {5'd15,3'd0}: chr = 6'd35;
            {5'd12,3'd1}: chr = 6'd36; {5'd13,3'd1}: chr = 6'd36; {5'd14,3'd1}: chr = 6'd36; {5'd15,3'd1}: chr = 6'd36;
            // 当前位置
            {5'd16,3'd0}: chr = 6'd40; {5'd16,3'd1}: chr = 6'd41; {5'd16,3'd2}: chr = 6'd22; {5'd16,3'd3}: chr = 6'd23;
            // 校园疏散平面图
            {5'd17,3'd0}: chr = 6'd42; {5'd17,3'd1}: chr = 6'd43; {5'd17,3'd2}: chr = 6'd44; {5'd17,3'd3}: chr = 6'd45;
            {5'd17,3'd4}: chr = 6'd46; {5'd17,3'd5}: chr = 6'd47; {5'd17,3'd6}: chr = 6'd4;
            // 页脚事件名
            {5'd18,3'd0}: chr = 6'd48; {5'd18,3'd1}: chr = 6'd49;
            {5'd19,3'd0}: chr = 6'd50; {5'd19,3'd1}: chr = 6'd51;
            {5'd20,3'd0}: chr = 6'd11; {5'd20,3'd1}: chr = 6'd12; {5'd20,3'd2}: chr = 6'd54;
            {5'd20,3'd3}: chr = 6'd20; {5'd20,3'd4}: chr = 6'd21;
            {5'd21,3'd0}: chr = 6'd52; {5'd21,3'd1}: chr = 6'd53;
            default:    chr = 6'd61;      // 空格
        endcase
    end

    reg        r3_val, r3_badge;
    reg [4:0]  r3_lid;
    reg [5:0]  r3_chr;
    reg [3:0]  r3_col, r3_row;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r3_val <= 1'b0; r3_badge <= 1'b0; r3_lid <= 5'd0;
            r3_chr <= 6'd61; r3_col <= 4'd0; r3_row <= 4'd0;
        end
        else begin
            r3_val   <= r2_val;
            r3_badge <= r2_badge;
            r3_lid   <= r2_lid;
            r3_chr   <= chr;
            r3_col   <= tx[3:0];
            r3_row   <= ty[3:0];
        end
    end

    // ==================================================================
    // R4：字形 ROM
    // ==================================================================
    wire [15:0] glyph_row;
    emergency_map_glyphs u_glyphs (
        .char_index (r3_chr),
        .row_index  (r3_row),
        .row_bits   (glyph_row)
    );

    reg        r4_val, r4_badge;
    reg [4:0]  r4_lid;
    reg [3:0]  r4_col;
    reg [15:0] r4_glyph;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r4_val <= 1'b0; r4_badge <= 1'b0; r4_lid <= 5'd0;
            r4_col <= 4'd0; r4_glyph <= 16'd0;
        end
        else begin
            r4_val   <= r3_val;
            r4_badge <= r3_badge;
            r4_lid   <= r3_lid;
            r4_col   <= r3_col;
            r4_glyph <= glyph_row;
        end
    end

    // ==================================================================
    // R5：位选 + 选色 + 角标红底覆盖
    //   颜色：危险/事故=白（危险区角标另有红底），推荐出口=浅绿，
    //         当前位置=浅蓝，页脚=暗蓝，正文=浅蓝
    // ==================================================================
    wire bit_sel = (r4_glyph >> (4'd15 - r4_col)) & 1'b1;
    wire lit     = r4_val && bit_sel;

    reg [23:0] tcol_rgb;
    always @(*) begin
        if (r4_lid == 5'd8 || r4_lid == 5'd9)        tcol_rgb = 24'hFFFFFF;
        else if (r4_lid == 5'd11)                    tcol_rgb = 24'h8CFFB4;
        else if (r4_lid == 5'd16)                    tcol_rgb = 24'hBFF0FF;
        else if (r4_lid == 5'd17 || r4_lid >= 5'd18) tcol_rgb = 24'h7FA6CC;
        else                                         tcol_rgb = 24'hC8E4FF;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            txt_rgb <= 24'd0; txt_alpha <= 8'd0;
        end
        else if (r4_badge) begin
            txt_rgb <= 24'hD81616; txt_alpha <= 8'd255;
        end
        else if (lit) begin
            txt_rgb <= tcol_rgb; txt_alpha <= 8'd255;
        end
        else begin
            txt_rgb <= 24'd0; txt_alpha <= 8'd0;
        end
    end

endmodule
