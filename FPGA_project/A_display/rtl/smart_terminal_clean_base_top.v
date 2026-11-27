`timescale 1ns/1ps

// Clean bring-up variant:
// TF/BMP -> SDRAM -> 1280x720 HDMI plus the embedded 48 kHz HDMI audio.
// All OSD, transition, emergency, brightness/contrast and audio visualization
// layers are disabled so the base video path can be inspected without clutter.
module smart_terminal_clean_base_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key_next,
    input  wire        key_auto,
    input  wire        key_emergency,

    output wire [5:0]  seg_sel,
    output wire [7:0]  seg_data,
    output wire [3:0]  led,

    output wire        HDMI_CLK_P,
    output wire        HDMI_D2_P,
    output wire        HDMI_D1_P,
    output wire        HDMI_D0_P,

    output wire        HDMI_DDC_SCL,
    inout  wire        HDMI_DDC_SDA,

    output wire        sd_ncs,
    output wire        sd_dclk,
    output wire        sd_mosi,
    input  wire        sd_miso
);

    smart_terminal_hw_top #(
        .FEATURE_MASK (5'h00)
    ) u_clean_base (
        .clk            (clk),
        .rst_n          (rst_n),
        .key_next       (key_next),
        .key_auto       (key_auto),
        .key_emergency  (1'b0),
        .seg_sel        (seg_sel),
        .seg_data       (seg_data),
        .led            (led),
        .HDMI_CLK_P     (HDMI_CLK_P),
        .HDMI_D2_P      (HDMI_D2_P),
        .HDMI_D1_P      (HDMI_D1_P),
        .HDMI_D0_P      (HDMI_D0_P),
        .HDMI_DDC_SCL   (HDMI_DDC_SCL),
        .HDMI_DDC_SDA   (HDMI_DDC_SDA),
        .sd_ncs         (sd_ncs),
        .sd_dclk        (sd_dclk),
        .sd_mosi        (sd_mosi),
        .sd_miso        (sd_miso)
    );

endmodule
