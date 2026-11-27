`timescale 1ns/1ps

module layer_compositor (
    input  wire        emergency,
    input  wire [11:0] x,
    input  wire [11:0] y,

    input  wire [23:0] base_rgb,
    input  wire [23:0] text_rgb,
    input  wire [7:0]  text_alpha,
    input  wire [23:0] bars_rgb,
    input  wire [7:0]  bars_alpha,
    input  wire [23:0] wave_rgb,
    input  wire [7:0]  wave_alpha,

    output wire [23:0] out_rgb
);

    wire [23:0] source_rgb = base_rgb;

    wire [23:0] text_mixed;
    wire [23:0] bars_mixed;
    wire [23:0] wave_mixed;

    alpha_blend u_text_blend (
        .base_rgb  (source_rgb),
        .layer_rgb (text_rgb),
        .alpha     (text_alpha),
        .out_rgb   (text_mixed)
    );

    alpha_blend u_bars_blend (
        .base_rgb  (text_mixed),
        .layer_rgb (bars_rgb),
        .alpha     (bars_alpha),
        .out_rgb   (bars_mixed)
    );

    alpha_blend u_wave_blend (
        .base_rgb  (bars_mixed),
        .layer_rgb (wave_rgb),
        .alpha     (wave_alpha),
        .out_rgb   (wave_mixed)
    );

    assign out_rgb = wave_mixed;

endmodule
