`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// emergency_map_mark -- “当前位置”脉冲标记
//
// 评委要能在 2~3 秒内回答“我在哪里”：白色实心点 + 青色描边 +
//   一圈不断向外扩散的脉冲环（半径由 plan 的 pulse 相位每帧 +1 驱动）。
//   环的阈值查平方 LUT，全程只有加减和比较。
//
// ★ 流水（统一 4 级内部寄存 R2..R5）：
//     R2：距标记中心的曼哈顿分解量（|dx|/|dy| 的低位、距离平方 d2、
//         near_ok、脉冲环内外阈值）
//     R3：实心点 / 描边 / 扩散环三个 1 bit 标志
//     R4：选色
//     R5：输出寄存器
// ---------------------------------------------------------------------------
module emergency_map_mark (
    input  wire        clk,
    input  wire        rst,
    input  wire [11:0] lx, ly,
    input  wire        per_en,
    input  wire [11:0] per_x, per_y,
    input  wire [3:0]  pulse,
    output reg  [23:0] mk_rgb,
    output reg  [7:0]  mk_alpha
);

    localparam [23:0] C_DOT  = 24'hFFFFFF;   // 中心实心点
    localparam [23:0] C_HALO = 24'h66DCFF;   // 常亮青色描边
    localparam [23:0] C_WAVE = 24'hBFF0FF;   // 扩散脉冲环

    function [7:0] sq4;
        input [3:0] d;
        begin
            case (d)
                4'd0: sq4 = 8'd0;    4'd1: sq4 = 8'd1;
                4'd2: sq4 = 8'd4;    4'd3: sq4 = 8'd9;
                4'd4: sq4 = 8'd16;   4'd5: sq4 = 8'd25;
                4'd6: sq4 = 8'd36;   4'd7: sq4 = 8'd49;
                4'd8: sq4 = 8'd64;   4'd9: sq4 = 8'd81;
                4'd10: sq4 = 8'd100; 4'd11: sq4 = 8'd121;
                4'd12: sq4 = 8'd144; 4'd13: sq4 = 8'd169;
                4'd14: sq4 = 8'd196; default: sq4 = 8'd225;
            endcase
        end
    endfunction

    // ==================================================================
    // R2 组合（只依赖 lx/ly 与 plan 的寄存器）
    // ==================================================================
    wire [11:0] adx = (lx >= per_x) ? (lx - per_x) : (per_x - lx);
    wire [11:0] ady = (ly >= per_y) ? (ly - per_y) : (per_y - ly);
    wire [7:0]  d2  = sq4(adx[3:0]) + sq4(ady[3:0]);
    wire near_ok = (adx[11:4] == 8'd0) && (ady[11:4] == 8'd0);

    wire [7:0] p_now = sq4(pulse);
    wire [7:0] p_sub = sq4(pulse - 4'd3);

    reg [7:0]  r2_d2;
    reg        r2_near, r2_en;
    reg [7:0]  r2_pnow, r2_psub;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r2_d2 <= 8'd0; r2_near <= 1'b0; r2_en <= 1'b0;
            r2_pnow <= 8'd0; r2_psub <= 8'd0;
        end
        else begin
            r2_d2   <= d2;
            r2_near <= near_ok;
            r2_en   <= per_en;
            r2_pnow <= p_now;
            r2_psub <= p_sub;
        end
    end

    // ==================================================================
    // R3 组合：三个标志（只依赖 R2 寄存器）
    // ==================================================================
    wire dot_n  = r2_near && (r2_d2 <= 8'd9);                       // r<=3 实心
    wire halo_n = r2_near && (r2_d2 > 8'd9) && (r2_d2 <= 8'd25);     // r=4..5 描边
    wire wave_n = r2_near && (r2_d2 <= r2_pnow) && (r2_d2 > r2_psub);

    reg r3_en, r3_dot, r3_halo, r3_wave;
    always @(posedge clk or posedge rst) begin
        if (rst) begin r3_en <= 1'b0; r3_dot <= 1'b0; r3_halo <= 1'b0; r3_wave <= 1'b0; end
        else begin
            r3_en   <= r2_en;
            r3_dot  <= dot_n;
            r3_halo <= halo_n;
            r3_wave <= wave_n;
        end
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
            if (r3_en && r3_dot)       begin r4_rgb <= C_DOT;  r4_a <= 8'd255; end
            else if (r3_en && r3_halo) begin r4_rgb <= C_HALO; r4_a <= 8'd255; end
            else if (r3_en && r3_wave) begin r4_rgb <= C_WAVE; r4_a <= 8'd220; end
            else                       begin r4_rgb <= 24'd0;  r4_a <= 8'd0;   end
        end
    end

    // ==================================================================
    // R5：输出寄存器
    // ==================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mk_rgb   <= 24'd0;
            mk_alpha <= 8'd0;
        end
        else begin
            mk_rgb   <= r4_rgb;
            mk_alpha <= r4_a;
        end
    end

endmodule
