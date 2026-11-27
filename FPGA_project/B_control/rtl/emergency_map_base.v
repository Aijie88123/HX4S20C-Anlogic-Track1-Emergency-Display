`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// emergency_map_base -- 动态疏散地图的“基础层”：深色底板 + 科技栅格 + 道路 +
//   8 栋建筑 + 中心操场（集合点）椭圆。
//
// 这一层是**纯几何**：与事件类型无关，任何时候(active=1)都画同一张图。
//
// ★ 流水（时序整改后统一为 4 级内部寄存，R2..R5）：
//   emergency_map_top 把窗口局部坐标寄存一拍（R1）后送给本模块，本模块再打 4 拍，
//   于是本模块的输出与宿主 s6_rgb 是同一个像素（详见 emergency_map_top 头注）。
//     R2：几何派生量（|dx|/|dy|、列内/行内局部坐标、道路/栅格/边框成员、虚线相位）
//     R3：成员判定 + 子色档位（椭圆/建筑），椭圆半宽 LUT 也在这一级
//     R4：优先级选色（6 选 1）
//     R5：输出寄存器（RGB + alpha，alpha 恒 255，窗口裁剪由 top 用哨兵坐标兜底）
//   把“判定”和“选色”分到不同拍，最长一段只剩 8 级左右组合逻辑
//   （改造前整层判定+选色挤在一拍，实测 15 级以上、19.5 ns，远超 13.333 ns 预算）。
//
// 全组合逻辑只有比较器、加减法和两个常量 LUT，没有乘法/除法/浮点。
// 椭圆（操场）用“每行半宽 LUT”实现：半宽在 elaboration 期由 oval_hw() 常量折叠
//   算出来，运行时只有一次“|dx| <= hw[|dy|]”的比较 —— 没有平方、没有开方。
// ---------------------------------------------------------------------------
module emergency_map_base #(
    parameter integer SCREEN_W = 1280,
    parameter integer SCREEN_H = 720,
    parameter integer MAP_XP0  = 26,
    parameter integer MAP_XP1  = 74,
    parameter integer MAP_YP0  = 43,
    parameter integer MAP_YP1  = 79
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [11:0] lx,          // 窗口局部 x（top 已寄存一拍）
    input  wire [11:0] ly,          // 窗口局部 y
    output reg  [23:0] base_rgb,
    output reg  [7:0]  base_alpha
);

    // ------------------------------------------------------------------
    // 锚点
    // ------------------------------------------------------------------
    // WW/WH 必须与 emergency_map_top 的窗口完全一致（947-332=615 / 568-309=259）。
    // 用"先整除再相减"而不是"(XP1-XP0) 乘宽度再除"，否则会差 1 px。
    localparam [11:0] WW   = (SCREEN_W*MAP_XP1/100) - (SCREEN_W*MAP_XP0/100);   // 615
    localparam [11:0] WH   = (SCREEN_H*MAP_YP1/100) - (SCREEN_H*MAP_YP0/100);   // 259

    localparam [11:0] COLW = WW*21/100;    // 建筑列宽 129
    localparam [11:0] CGAP = WW*4/100;     // 列间通道 24
    localparam [11:0] BX0  = WW*3/100;     // 第一列左边 18
    localparam [11:0] ROWH = WH*17/100;    // 建筑行高 44
    localparam [11:0] TOPY = WH*5/100;     // 上排顶 12
    localparam [11:0] BOTY = WH*59/100;    // 下排顶 152

    localparam [11:0] RAY  = WH*25/100;    // 主干道 A 中线 64
    localparam [11:0] RBY  = WH*56/100;    // 主干道 B 中线 145
    localparam [11:0] RBY2 = WH*80/100;    // 次干道 B 中线 207
    localparam [11:0] RHLF = WH*3/100;     // 道路半宽 7 (道路宽 14)

    localparam [11:0] OVX  = WW*50/100;    // 操场中心 307
    localparam [11:0] OVY  = WH*40/100;    // 103
    localparam [11:0] ORX  = WW*21/100;    // 半长轴 129
    localparam [11:0] ORY  = WH*12/100;    // 半短轴 31

    // 列左边界：BX0 + k*(COLW+CGAP)
    localparam [11:0] C0L = BX0;
    localparam [11:0] C1L = BX0 + COLW + CGAP;
    localparam [11:0] C2L = BX0 + 2*(COLW + CGAP);
    localparam [11:0] C3L = BX0 + 3*(COLW + CGAP);
    localparam [11:0] C0R = C0L + COLW;
    localparam [11:0] C1R = C1L + COLW;
    localparam [11:0] C2R = C2L + COLW;
    localparam [11:0] C3R = C3L + COLW;
    localparam [11:0] R0B = TOPY + ROWH;
    localparam [11:0] R1B = BOTY + ROWH;

    // 纵向道路中线（列间通道中心）
    localparam [11:0] GX1 = C0R + CGAP/2;
    localparam [11:0] GX2 = C1R + CGAP/2;
    localparam [11:0] GX3 = C2R + CGAP/2;
    localparam [11:0] GVW = WW*2/100;      // 纵向道路半宽 12

    // ------------------------------------------------------------------
    // 配色（深色科技感，全图只用这一组色）
    // ------------------------------------------------------------------
    localparam [23:0] C_BG      = 24'h12233A;   // 底板
    localparam [23:0] C_GRID    = 24'h172C47;   // 科技栅格
    localparam [23:0] C_FRAME   = 24'h1C3E63;   // 窗口内边框
    localparam [23:0] C_ROAD    = 24'h1E3C5E;   // 道路
    localparam [23:0] C_ROADLN  = 24'h3E6E9E;   // 道路中线
    localparam [23:0] C_BLDG    = 24'h1B3557;   // 建筑填充
    localparam [23:0] C_BLDGT   = 24'h24456C;   // 建筑顶面（内缩带）
    localparam [23:0] C_BLDGE   = 24'h2A5B96;   // 建筑描边
    localparam [23:0] C_GRASS   = 24'h123A2A;   // 操场填充
    localparam [23:0] C_TRACK   = 24'h21A05E;   // 跑道外圈
    localparam [23:0] C_TRACK2  = 24'h1B6B44;   // 跑道内圈

    // ------------------------------------------------------------------
    // 椭圆半宽 LUT：|dy| -> 半宽（elaboration 期常量折叠，运行时只有比较）
    // ------------------------------------------------------------------
    function [11:0] oval_hw;
        input integer i;
        integer k;
        begin
            oval_hw = 0;
            for (k = 0; k <= (ORX + 2); k = k + 1) begin
                if ((k*k*ORY*ORY) <= (ORX*ORX*(ORY*ORY - i*i)))
                    oval_hw = k;
            end
        end
    endfunction

    // ==================================================================
    // R2 组合：几何派生量（全部只依赖 lx/ly，即 R1 寄存器）
    // ==================================================================
    // 注意：|dy| 最大 = WH-1 - OVY = 155，必须 12 bit。曾经写成 5 bit，
    //   截断后 |dy| 永远 <= 31，in_oval 大面积误判，把整张底板刷成操场绿。
    wire [11:0] ady = (ly >= OVY) ? (ly - OVY) : (OVY - ly);
    wire [11:0] adx = (lx >= OVX) ? (lx - OVX) : (OVX - lx);

    wire in_row0 = (ly >= TOPY) && (ly < R0B);
    wire in_row1 = (ly >= BOTY) && (ly < R1B);

    // 列内/行内局部坐标：一次减法 + 一次选择，避免 8 组重复减法
    wire [11:0] col_lx = (lx >= C3L) ? (lx - C3L) :
                         (lx >= C2L) ? (lx - C2L) :
                         (lx >= C1L) ? (lx - C1L) : (lx - C0L);
    wire [11:0] row_ly = in_row1 ? (ly - BOTY) : (ly - TOPY);

    wire in_ray  = (ly >= (RAY  - RHLF)) && (ly <= (RAY  + RHLF));
    wire in_rby  = (ly >= (RBY  - RHLF)) && (ly <= (RBY  + RHLF));
    wire in_rby2 = (ly >= (RBY2 - RHLF)) && (ly <= (RBY2 + RHLF));
    wire in_gv1  = (lx >= (GX1 - GVW)) && (lx <= (GX1 + GVW));
    wire in_gv2  = (lx >= (GX2 - GVW)) && (lx <= (GX2 + GVW));
    wire in_gv3  = (lx >= (GX3 - GVW)) && (lx <= (GX3 + GVW));

    wire on_cross = in_gv1 || in_gv2 || in_gv3;
    wire in_road  = in_ray || in_rby || in_rby2 || on_cross;

    wire dash = ((lx + ly) & 12'd15) < 12'd8;
    wire in_centerline = ((ly == RAY)  && in_ray  && !on_cross) ||
                         ((ly == RBY)  && in_rby  && !on_cross) ||
                         ((ly == RBY2) && in_rby2 && !on_cross) ||
                         (((lx == GX1) || (lx == GX2) || (lx == GX3)) && in_road);
    wire roadln_c = in_centerline && dash;

    // 科技栅格：16 px 一条极暗细线；窗口内边框
    wire in_grid  = (lx[3:0] == 4'd0) || (ly[3:0] == 4'd0);
    wire in_frame = (lx == 12'd0) || (ly == 12'd0) ||
                    (lx == (WW - 12'd1)) || (ly == (WH - 12'd1));

    reg [11:0] r2_adx, r2_ady, r2_collx, r2_rowly;
    reg        r2_row0, r2_row1, r2_road, r2_roadln, r2_frame, r2_grid;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r2_adx <= 12'd0; r2_ady <= 12'd0; r2_collx <= 12'd0; r2_rowly <= 12'd0;
            r2_row0 <= 1'b0; r2_row1 <= 1'b0; r2_road <= 1'b0; r2_roadln <= 1'b0;
            r2_frame <= 1'b0; r2_grid <= 1'b0;
        end
        else begin
            r2_adx   <= adx;
            r2_ady   <= ady;
            r2_collx <= col_lx;
            r2_rowly <= row_ly;
            r2_row0  <= in_row0;
            r2_row1  <= in_row1;
            r2_road  <= in_road;
            r2_roadln <= roadln_c;
            r2_frame <= in_frame;
            r2_grid  <= in_grid;
        end
    end

    // ==================================================================
    // R3 组合：成员判定 + 子色档位（只依赖 R2 寄存器）
    // ==================================================================
    reg [11:0] o_hw, o_hw2;
    always @(*) begin
        case (r2_ady)
            5'd0:  begin o_hw = oval_hw(0);  o_hw2 = oval_hw(1);  end
            5'd1:  begin o_hw = oval_hw(1);  o_hw2 = oval_hw(2);  end
            5'd2:  begin o_hw = oval_hw(2);  o_hw2 = oval_hw(3);  end
            5'd3:  begin o_hw = oval_hw(3);  o_hw2 = oval_hw(4);  end
            5'd4:  begin o_hw = oval_hw(4);  o_hw2 = oval_hw(5);  end
            5'd5:  begin o_hw = oval_hw(5);  o_hw2 = oval_hw(6);  end
            5'd6:  begin o_hw = oval_hw(6);  o_hw2 = oval_hw(7);  end
            5'd7:  begin o_hw = oval_hw(7);  o_hw2 = oval_hw(8);  end
            5'd8:  begin o_hw = oval_hw(8);  o_hw2 = oval_hw(9);  end
            5'd9:  begin o_hw = oval_hw(9);  o_hw2 = oval_hw(10); end
            5'd10: begin o_hw = oval_hw(10); o_hw2 = oval_hw(11); end
            5'd11: begin o_hw = oval_hw(11); o_hw2 = oval_hw(12); end
            5'd12: begin o_hw = oval_hw(12); o_hw2 = oval_hw(13); end
            5'd13: begin o_hw = oval_hw(13); o_hw2 = oval_hw(14); end
            5'd14: begin o_hw = oval_hw(14); o_hw2 = oval_hw(15); end
            5'd15: begin o_hw = oval_hw(15); o_hw2 = oval_hw(16); end
            5'd16: begin o_hw = oval_hw(16); o_hw2 = oval_hw(17); end
            5'd17: begin o_hw = oval_hw(17); o_hw2 = oval_hw(18); end
            5'd18: begin o_hw = oval_hw(18); o_hw2 = oval_hw(19); end
            5'd19: begin o_hw = oval_hw(19); o_hw2 = oval_hw(20); end
            5'd20: begin o_hw = oval_hw(20); o_hw2 = oval_hw(21); end
            5'd21: begin o_hw = oval_hw(21); o_hw2 = oval_hw(22); end
            5'd22: begin o_hw = oval_hw(22); o_hw2 = oval_hw(23); end
            5'd23: begin o_hw = oval_hw(23); o_hw2 = oval_hw(24); end
            5'd24: begin o_hw = oval_hw(24); o_hw2 = oval_hw(25); end
            5'd25: begin o_hw = oval_hw(25); o_hw2 = oval_hw(26); end
            5'd26: begin o_hw = oval_hw(26); o_hw2 = oval_hw(27); end
            5'd27: begin o_hw = oval_hw(27); o_hw2 = oval_hw(28); end
            5'd28: begin o_hw = oval_hw(28); o_hw2 = oval_hw(29); end
            5'd29: begin o_hw = oval_hw(29); o_hw2 = oval_hw(30); end
            5'd30: begin o_hw = oval_hw(30); o_hw2 = oval_hw(31); end
            12'd31: begin o_hw = oval_hw(31); o_hw2 = oval_hw(32); end
            12'd32: begin o_hw = oval_hw(32); o_hw2 = oval_hw(33); end
            12'd33: begin o_hw = oval_hw(33); o_hw2 = oval_hw(34); end
            12'd34: begin o_hw = oval_hw(34); o_hw2 = oval_hw(35); end
            12'd35: begin o_hw = oval_hw(35); o_hw2 = oval_hw(36); end
            12'd36: begin o_hw = oval_hw(36); o_hw2 = oval_hw(37); end
            12'd37: begin o_hw = oval_hw(37); o_hw2 = oval_hw(38); end
            12'd38: begin o_hw = oval_hw(38); o_hw2 = oval_hw(39); end
            12'd39: begin o_hw = oval_hw(39); o_hw2 = oval_hw(40); end
            12'd40: begin o_hw = oval_hw(40); o_hw2 = oval_hw(41); end
            12'd41: begin o_hw = oval_hw(41); o_hw2 = oval_hw(42); end
            12'd42: begin o_hw = oval_hw(42); o_hw2 = oval_hw(43); end
            12'd43: begin o_hw = oval_hw(43); o_hw2 = oval_hw(44); end
            default: begin o_hw = 12'd0; o_hw2 = 12'd0; end   // ady > ORY: 不在椭圆内
        endcase
    end

    wire in_oval = (r2_ady <= ORY) && (r2_adx <= o_hw);
    wire [1:0] oval_sel = !in_oval                                              ? 2'd0 :
                          ((r2_adx > (o_hw  - 12'd3)) || (r2_ady > (ORY - 12'd2))) ? 2'd1 :
                          (r2_adx > (o_hw2 - 12'd2))                            ? 2'd2 : 2'd3;

    wire near_edge_x = (r2_collx == 12'd0) || (r2_collx == COLW - 12'd1) ||
                       (r2_collx == 12'd1) || (r2_collx == COLW - 12'd2);
    wire near_edge_y = (r2_rowly == 12'd0) || (r2_rowly == ROWH - 12'd1) ||
                       (r2_rowly == 12'd1) || (r2_rowly == ROWH - 12'd2);
    wire in_bldg = (r2_row0 || r2_row1) && (r2_collx < COLW);
    wire in_roof = in_bldg && (r2_collx > 12'd3) && (r2_collx < (COLW - 12'd4)) &&
                             (r2_rowly > 12'd3) && (r2_rowly < (ROWH - 12'd4));
    wire [1:0] bldg_sel = !in_bldg                    ? 2'd0 :
                          (near_edge_x || near_edge_y) ? 2'd1 :
                          (in_roof ? 2'd2 : 2'd3);

    reg        r3_oval, r3_bldg, r3_road, r3_roadln, r3_frame, r3_grid;
    reg [1:0]  r3_ovsel, r3_blsel;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r3_oval <= 1'b0; r3_bldg <= 1'b0; r3_road <= 1'b0; r3_roadln <= 1'b0;
            r3_frame <= 1'b0; r3_grid <= 1'b0; r3_ovsel <= 2'd0; r3_blsel <= 2'd0;
        end
        else begin
            r3_oval   <= in_oval;
            r3_ovsel  <= oval_sel;
            r3_bldg   <= in_bldg;
            r3_blsel  <= bldg_sel;
            r3_road   <= r2_road;
            r3_roadln <= r2_roadln;
            r3_frame  <= r2_frame;
            r3_grid   <= r2_grid;
        end
    end

    // ==================================================================
    // R4：优先级选色（建筑 > 道路 > 边框 > 栅格 > 底板；操场独立优先）
    // ==================================================================
    reg [23:0] r4_rgb;
    always @(posedge clk or posedge rst) begin
        if (rst) r4_rgb <= 24'd0;
        else begin
            if (r3_oval)       r4_rgb <= (r3_ovsel == 2'd1) ? C_TRACK :
                                        (r3_ovsel == 2'd2) ? C_TRACK2 : C_GRASS;
            else if (r3_bldg)  r4_rgb <= (r3_blsel == 2'd1) ? C_BLDGE :
                                        (r3_blsel == 2'd2) ? C_BLDGT : C_BLDG;
            else if (r3_road)  r4_rgb <= r3_roadln ? C_ROADLN : C_ROAD;
            else if (r3_frame) r4_rgb <= C_FRAME;
            else if (r3_grid)  r4_rgb <= C_GRID;
            else               r4_rgb <= C_BG;
        end
    end

    // ==================================================================
    // R5：输出寄存器（alpha 恒 255；窗口外由 top 的哨兵坐标 + alpha 门控兜底）
    // ==================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            base_rgb   <= 24'd0;
            base_alpha <= 8'd0;
        end
        else begin
            base_rgb   <= r4_rgb;
            base_alpha <= 8'd255;
        end
    end

endmodule
