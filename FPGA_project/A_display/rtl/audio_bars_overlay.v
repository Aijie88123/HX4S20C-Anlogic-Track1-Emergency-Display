`timescale 1ns/1ps

// 右下角音频能量条
//
// 相对上一版的改动：
//   1. 区域从 128x96 放大到 256x160，柱子从 8 px 加宽到 16 px 间距，
//      在 1280x720 上肉眼一眼能看到。
//   2. 增益重算：audio_mag 满幅约 0x1E84（24 位样本绝对值的高 16 位），
//      取 [13:6] 让满幅落在 0x7A 附近，柱子能用掉面板高度的大约 9 成；
//      旧版取 [15:8] 再右移 2 位，满幅只有 1/5 高，几乎看不出起伏。
//   3. 面板加深色底和边框，柱子变化时对比明显。
module audio_bars_overlay #(
    parameter integer SCREEN_W = 1280,
    parameter integer SCREEN_H = 720,
    // 显示区域（右下角，但避开底部滚动字幕）
    parameter integer BAR_W = 256,
    parameter integer BAR_H = 160,
    parameter integer BAR_X = SCREEN_W - 256 - 48,
    parameter integer BAR_Y = SCREEN_H - 160 - 70
) (
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire [15:0] audio_mag,

    output reg  [23:0] bars_rgb,
    output reg  [7:0]  bars_alpha
);

    localparam integer BAR_LEFT   = BAR_X;
    localparam integer BAR_RIGHT  = BAR_X + BAR_W - 1;
    localparam integer BAR_TOP    = BAR_Y;
    localparam integer BAR_BOTTOM = BAR_Y + BAR_H - 1;

    localparam integer BAR_PITCH  = 16;   // 每根柱子占用的横向像素
    localparam integer BAR_WIDTH  = 12;   // 柱子实际宽度，留 4 px 间隙

    wire in_region = (x >= BAR_LEFT) && (x <= BAR_RIGHT) &&
                     (y >= BAR_TOP)  && (y <= BAR_BOTTOM);

    wire [3:0] bar_index = (x - BAR_LEFT) / BAR_PITCH;
    wire [3:0] bar_col   = (x - BAR_LEFT) % BAR_PITCH;

    // 满幅饱和到 127，保证 bar_height 不会顶穿面板下沿
    wire [7:0] energy = (audio_mag[13:6] > 8'd127) ? 8'd127 : audio_mag[13:6];

    wire [9:0] bar_height = 10'd6 + {2'b0, energy} + {6'b0, bar_index};
    wire [9:0] bar_top_px = BAR_BOTTOM - bar_height;

    wire bar_fill = in_region && (y >= bar_top_px) && (bar_col < BAR_WIDTH);

    wire bar_frame = in_region &&
                     (((x - BAR_LEFT) < 3) ||
                      ((x - BAR_LEFT) >= (BAR_W - 3)) ||
                      ((y - BAR_TOP)  < 3) ||
                      ((y - BAR_TOP)  >= (BAR_H - 3)));

    function [23:0] bar_color;
        input [3:0] idx;
        begin
            case (idx[2:0])
                3'd0: bar_color = 24'h28C7FA;
                3'd1: bar_color = 24'h30D98B;
                3'd2: bar_color = 24'hF2C94C;
                3'd3: bar_color = 24'hF2994A;
                3'd4: bar_color = 24'hEB5757;
                3'd5: bar_color = 24'hBB6BD9;
                3'd6: bar_color = 24'h2D9CDB;
                default: bar_color = 24'h56CCF2;
            endcase
        end
    endfunction

    always @(*) begin
        if (bar_fill) begin
            bars_rgb   = bar_color(bar_index);
            bars_alpha = 8'd230;
        end
        else if (bar_frame) begin
            bars_rgb   = 24'h2E6FA8;
            bars_alpha = 8'd210;
        end
        else if (in_region) begin
            bars_rgb   = 24'h061420;
            bars_alpha = 8'd150;
        end
        else begin
            bars_rgb   = 24'h000000;
            bars_alpha = 8'd0;
        end
    end

endmodule
