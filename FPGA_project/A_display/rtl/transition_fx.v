`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// transition_fx -- 棋盘转场的相位发生器
//
// fx_sel 3 生成像素的滞后相位，并钳位到 SPREAD。
// 0/1/2/4/5/6/7 输出零相位；这些编码的普通转场禁用由调用方处理。
// 对角扫及菱形转场的坐标加法、中心距离逻辑已移除。
// SCREEN_W/SCREEN_H 仅保留参数接口兼容，不参与相位计算。
// 纯组合逻辑，输出由调用方打一拍（和 s1_trans_black 同拍）。
// ---------------------------------------------------------------------------
module transition_fx #(
    parameter integer SCREEN_W = 1280,
    parameter integer SCREEN_H = 720,
    parameter [7:0]   SPREAD   = 8'd128
) (
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire [2:0]  fx_sel,
    output reg  [7:0]  phase
);

    // 先算出原始值（可能超过 SPREAD），再统一钳位
    reg [11:0] raw;

    always @(*) begin
        case (fx_sel)
            // 3 棋盘格：64x64 的块交替，相邻块反向
            3'd3: raw = (x[6] ^ y[6]) ? 12'd128 : 12'd0;
            // 已删除的普通效果编码均为零相位
            default: raw = 12'd0;
        endcase
    end

    always @(*) begin
        // Equality also produces SPREAD on the unclamped branch. Using >=
        // is bit-identical and lets the default power-of-two limit become
        // a high-bit test instead of a carry-chain comparator.
        if (raw >= SPREAD)
            phase = SPREAD;
        else
            phase = raw[7:0];
    end

endmodule
