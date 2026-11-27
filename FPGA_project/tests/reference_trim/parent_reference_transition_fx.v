`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// transition_trim_parent_fx -- 转场图案相位发生器（赛题扩展要求②，A 类：单缓冲图案化淡入淡出）
//
// 给每个像素算一个 0..SPREAD 的"滞后相位" phase：
// 相越大的区域越晚变暗、也越晚变亮。把 phase 从全局淡入淡出系数里减掉，
// 就得到该像素自己的 alpha，屏幕上就出现各种图案化的转场。
//
// 为什么相位只影响"错开"而不破坏"切图那一拍必须全黑"：
//   叠加层用的是
//       alpha_wide = fade_alpha + (fade_alpha >> 1)        // 增益 1.5，0..382
//       local      = clamp(alpha_wide - phase, 0, 255)
//   fade_alpha 到 255（也就是切图那一拍）时，alpha_wide = 382，
//   即使 phase 取满 128，local 仍是 254/255 —— 全黑。
//   如果直接写 clamp(fade_alpha - phase)，相位大的区域在切图时还亮着，
//   缓冲区切换就露馅了。**增益那 1.5 倍不能省。**
//
// 纯组合逻辑，输出由调用方打一拍（和 s1_trans_black 同拍）。
// 0..5 保留相位淡变；已删除二值左右揭幕，输入 6/7 在叠加层使用均匀淡变 alpha。
// ---------------------------------------------------------------------------
module transition_trim_parent_fx #(
    parameter integer SCREEN_W = 1280,
    parameter integer SCREEN_H = 720,
    parameter [7:0]   SPREAD   = 8'd128
) (
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire [2:0]  fx_sel,
    output reg  [7:0]  phase
);

    localparam [11:0] CX     = SCREEN_W / 2;
    localparam [11:0] CY = SCREEN_H / 2;

    // 从中心出发的曼哈顿距离：|dx| + |dy|
    wire [11:0] dx = (x > CX) ? (x - CX) : (CX - x);
    wire [11:0] dy = (y > CY) ? (y - CY) : (CY - y);

    // 先算出原始值（可能超过 SPREAD），再统一钳位
    reg [11:0] raw;

    always @(*) begin
        case (fx_sel)
            // 0 均匀淡入淡出：所有像素同步，等价于原来的效果
            3'd0: raw = 12'd0;
            // 1 横向百叶窗：每 8 行一档，同一条带里的行同步变暗
            3'd1: raw = {5'd0, y[2:0], 4'b0000};            // 0,16,...,112
            // 2 竖向百叶窗：每 8 列一档
            3'd2: raw = {5'd0, x[2:0], 4'b0000};
            // 3 棋盘格：64x64 的块交替，相邻块反向
            3'd3: raw = (x[6] ^ y[6]) ? 12'd128 : 12'd0;
            // 4 对角扫：左上角先变，沿对角线推进。
            // 注意要写 x[11:4]（= x>>4，0..79）而不是 x[7:4]（只取 4 个比特，0..15）——
            // 后者会让整个屏幕的相位挤在 0..30，图案基本看不出来。
            3'd4: raw = {4'd0, x[11:4]} + {4'd0, y[11:4]};
            // 5 菱形：从画面中心向四周扩散
            3'd5: raw = (dx + dy) >> 3;
            // 保留未使用编码的透明兼容相位；主叠加层把 6/7 映射到均匀淡变。
            3'd6, 3'd7: raw = 12'd0;
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
