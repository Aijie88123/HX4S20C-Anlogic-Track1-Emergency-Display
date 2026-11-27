`timescale 1ns/1ps

module alpha_blend (
    input  wire [23:0] base_rgb,
    input  wire [23:0] layer_rgb,
    input  wire [7:0]  alpha,
    output wire [23:0] out_rgb
);

    // out = (base*(255-a) + layer*a) / 255
    //
    // 旧实现用 mixed[15:8] 即除以 256，导致：
    //   a=0   时输出 base*255/256，画面被整体压暗 1 个 LSB
    //   a=255 时输出 layer*255/256，纯色叠加层（如应急红框 FF2020）永远差 1
    // 四层叠加逐级压暗，成片会比原图更暗。
    //
    // 这里改用 n/255 的整数等价式：
    //   n/255 = (n + (n>>8) + 1) >> 8     (对 n <= 65535 精确)
    // 使得 a=0 原样透传、a=255 精确取 layer。
    function [7:0] blend_channel;
        input [7:0] base;
        input [7:0] layer;
        input [7:0] a;
        reg [16:0] mixed;
        reg [16:0] corrected;
        begin
            mixed = (base * (8'd255 - a)) + (layer * a);
            corrected = mixed + (mixed >> 8) + 17'd1;
            blend_channel = corrected[15:8];
        end
    endfunction

    assign out_rgb[23:16] = blend_channel(base_rgb[23:16], layer_rgb[23:16], alpha);
    assign out_rgb[15:8]  = blend_channel(base_rgb[15:8],  layer_rgb[15:8],  alpha);
    assign out_rgb[7:0]   = blend_channel(base_rgb[7:0],   layer_rgb[7:0],   alpha);

endmodule
