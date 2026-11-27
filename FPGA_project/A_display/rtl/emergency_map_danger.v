`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// emergency_map_danger -- 危险区 + 事故点
//
// 危险区是“矩形 + 红色填充 + 斜纹 + 红色虚线边框”四件套：
//   - 填充颜色随 blink_on 在暗红/亮红之间呼吸（宿主把 alpha 当 1 bit 用，
//     所以“呼吸”必须靠颜色，不能靠 alpha）；
//   - 斜纹用 (lx+ly) 低 3 位做 45 度条纹，复刻设计稿里的斜线阴影；
//   - 虚线边框同样取模；
//   - 事故点是同心圆靶心 + 由 pulse 驱动的一圈扩散环。
//
// ★ 流水（统一 4 级内部寄存 R2..R5）：
//     R2：矩形/边框/斜纹/靶心/扩散环全部判成 1 bit 标志
//     R3：类别码（事故靶心 > 事故环 > 虚线边框 > 填充/斜纹）
//     R4：按类别选色（填充色还要看 blink_on 呼吸相位）
//     R5：输出寄存器
//   整块判定挤在一拍时组合深度 15 级（17.8 ns），拆开后最长的一段只剩标志判定。
//
// 圆判据：|d| 的平方查 16 项 LUT（sq3），距离平方只有一次加法一次比较，
//   没有乘法器；扩散环的阈值同样查 LUT（sq_p），也没有乘法。
// ---------------------------------------------------------------------------
module emergency_map_danger (
    input  wire        clk,
    input  wire        rst,
    input  wire [11:0] lx, ly,
    input  wire        blink_on,
    input  wire [3:0]  pulse,

    input  wire        d0_en,
    input  wire [11:0] d0_x0, d0_y0, d0_x1, d0_y1,
    input  wire        d1_en,
    input  wire [11:0] d1_x0, d1_y0, d1_x1, d1_y1,
    input  wire        acc_en,
    input  wire [11:0] acc_x, acc_y,

    output reg  [23:0] dgr_rgb,
    output reg  [7:0]  dgr_alpha
);

    localparam [23:0] C_FILL_LO = 24'h5A1015;  // 危险区填充 · 暗相
    localparam [23:0] C_FILL_HI = 24'h7E1A1E;  // 危险区填充 · 亮相（呼吸）
    localparam [23:0] C_HATCH   = 24'h8E2226;  // 危险区 45° 斜纹
    localparam [23:0] C_EDGE    = 24'hFF3B3B;  // 危险区虚线边框
    localparam [23:0] C_ACC     = 24'hFFFFFF;  // 事故点靶心
    localparam [23:0] C_RING    = 24'hFF8A8A;  // 事故点扩散环

    // ==================================================================
    // R2 组合：全部标志（只依赖 lx/ly 与 plan 的寄存器）
    // ==================================================================
    wire in_d0 = d0_en && (lx >= d0_x0) && (lx <= d0_x1) &&
                          (ly >= d0_y0) && (ly <= d0_y1);
    wire in_d1 = d1_en && (lx >= d1_x0) && (lx <= d1_x1) &&
                          (ly >= d1_y0) && (ly <= d1_y1);
    wire in_any_n = in_d0 || in_d1;

    wire [11:0] bx0 = in_d1 ? d1_x0 : d0_x0;
    wire [11:0] by0 = in_d1 ? d1_y0 : d0_y0;
    wire [11:0] bx1 = in_d1 ? d1_x1 : d0_x1;
    wire [11:0] by1 = in_d1 ? d1_y1 : d0_y1;

    wire [11:0] ex = (lx >= bx0) ? (lx - bx0) : (bx0 - lx);
    wire [11:0] ey = (ly >= by0) ? (ly - by0) : (by0 - ly);
    wire on_edge_n = (ex <= 12'd1) || (ey <= 12'd1) ||
                     (lx >= (bx1 - 12'd1)) || (ly >= (by1 - 12'd1));
    wire [11:0] cross = lx + ly;
    wire dash_on_n = cross[2:0] < 3'd4;
    wire hatch_n   = cross[2:0] < 3'd3;

    // ---- 平方 LUT ----
    function [7:0] sq3;                       // 0..15 -> d^2
        input [3:0] d;
        begin
            case (d)
                4'd0: sq3 = 8'd0;    4'd1: sq3 = 8'd1;
                4'd2: sq3 = 8'd4;    4'd3: sq3 = 8'd9;
                4'd4: sq3 = 8'd16;   4'd5: sq3 = 8'd25;
                4'd6: sq3 = 8'd36;   4'd7: sq3 = 8'd49;
                4'd8: sq3 = 8'd64;   4'd9: sq3 = 8'd81;
                4'd10: sq3 = 8'd100; 4'd11: sq3 = 8'd121;
                4'd12: sq3 = 8'd144; 4'd13: sq3 = 8'd169;
                4'd14: sq3 = 8'd196; default: sq3 = 8'd225;
            endcase
        end
    endfunction

    wire [11:0] adx = (lx >= acc_x) ? (lx - acc_x) : (acc_x - lx);
    wire [11:0] ady = (ly >= acc_y) ? (ly - acc_y) : (acc_y - ly);
    wire [7:0]  d2  = sq3(adx[3:0]) + sq3(ady[3:0]);
    wire near_ok = (adx[11:4] == 8'd0) && (ady[11:4] == 8'd0);

    wire [7:0] p_now = sq3(pulse);
    wire [7:0] p_sub = sq3(pulse - 4'd4);

    wire acc_core_n = near_ok && (d2 <= 8'd4);                     // r<=2 实心靶心
    wire acc_r1_n   = near_ok && (d2 > 8'd16) && (d2 <= 8'd25);    // r=5 定标环
    wire acc_pul_n  = near_ok && (d2 <= p_now) && (d2 > p_sub);    // 扩散环
    wire acc_ring_n = acc_r1_n || acc_pul_n;

    reg f_any, f_edge, f_dash, f_hatch, f_accen, f_acccore, f_accring;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            f_any <= 1'b0; f_edge <= 1'b0; f_dash <= 1'b0; f_hatch <= 1'b0;
            f_accen <= 1'b0; f_acccore <= 1'b0; f_accring <= 1'b0;
        end
        else begin
            f_any     <= in_any_n;
            f_edge    <= on_edge_n;
            f_dash    <= dash_on_n;
            f_hatch   <= hatch_n;
            f_accen   <= acc_en;
            f_acccore <= acc_core_n;
            f_accring <= acc_ring_n;
        end
    end

    // ==================================================================
    // R3 组合：类别码（只依赖 R2 寄存器）
    //   4=事故靶心 3=事故扩散环 2=虚线边框 1=填充/斜纹 0=无
    // ==================================================================
    wire [2:0] cls_n = (f_accen && f_acccore) ? 3'd4 :
                       (f_accen && f_accring) ? 3'd3 :
                       (f_any && f_edge && f_dash) ? 3'd2 :
                       f_any ? 3'd1 : 3'd0;

    reg [2:0] r3_cls;
    reg       r3_hatch;
    always @(posedge clk or posedge rst) begin
        if (rst) begin r3_cls <= 3'd0; r3_hatch <= 1'b0; end
        else     begin r3_cls <= cls_n; r3_hatch <= f_hatch; end
    end

    // ==================================================================
    // R4：选色（事故点 > 虚线边框 > 填充/斜纹；填充随 blink_on 呼吸）
    // ==================================================================
    reg [23:0] r4_rgb;
    reg [7:0]  r4_a;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r4_rgb <= 24'd0; r4_a <= 8'd0;
        end
        else begin
            case (r3_cls)
                3'd4:    begin r4_rgb <= C_ACC;  r4_a <= 8'd255; end
                3'd3:    begin r4_rgb <= C_RING; r4_a <= 8'd255; end
                3'd2:    begin r4_rgb <= C_EDGE; r4_a <= 8'd255; end
                3'd1:    begin r4_rgb <= r3_hatch ? C_HATCH : (blink_on ? C_FILL_HI : C_FILL_LO);
                                r4_a <= 8'd255; end
                default: begin r4_rgb <= 24'd0; r4_a <= 8'd0; end
            endcase
        end
    end

    // ==================================================================
    // R5：输出寄存器
    // ==================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dgr_rgb   <= 24'd0;
            dgr_alpha <= 8'd0;
        end
        else begin
            dgr_rgb   <= r4_rgb;
            dgr_alpha <= r4_a;
        end
    end

endmodule
