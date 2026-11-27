`timescale 1ns/1ps

`define FEATURE_TOP_PORTS \
    input  wire        clk, \
    input  wire        rst_n, \
    input  wire        key_next, \
    input  wire        key_auto, \
    input  wire        key_emergency, \
    output wire [5:0]  seg_sel, \
    output wire [7:0]  seg_data, \
    output wire [3:0]  led, \
    output wire        HDMI_CLK_P, \
    output wire        HDMI_D2_P, \
    output wire        HDMI_D1_P, \
    output wire        HDMI_D0_P, \
    output wire        HDMI_DDC_SCL, \
    inout  wire        HDMI_DDC_SDA, \
    output wire        sd_ncs, \
    output wire        sd_dclk, \
    output wire        sd_mosi, \
    input  wire        sd_miso

`define FEATURE_TOP_CONNECTIONS \
    .clk          (clk), \
    .rst_n        (rst_n), \
    .key_next     (key_next), \
    .key_auto     (key_auto), \
    .key_emergency(key_emergency), \
    .seg_sel      (seg_sel), \
    .seg_data     (seg_data), \
    .led          (led), \
    .HDMI_CLK_P   (HDMI_CLK_P), \
    .HDMI_D2_P    (HDMI_D2_P), \
    .HDMI_D1_P    (HDMI_D1_P), \
    .HDMI_D0_P    (HDMI_D0_P), \
    .HDMI_DDC_SCL (HDMI_DDC_SCL), \
    .HDMI_DDC_SDA (HDMI_DDC_SDA), \
    .sd_ncs       (sd_ncs), \
    .sd_dclk      (sd_dclk), \
    .sd_mosi      (sd_mosi), \
    .sd_miso      (sd_miso)

module smart_terminal_base_top (`FEATURE_TOP_PORTS);
    smart_terminal_hw_top #(.FEATURE_MASK(5'h00)) u_top (`FEATURE_TOP_CONNECTIONS);
endmodule

module smart_terminal_scroll_top (`FEATURE_TOP_PORTS);
    smart_terminal_hw_top #(.FEATURE_MASK(5'h01)) u_top (`FEATURE_TOP_CONNECTIONS);
endmodule

module smart_terminal_transition_top (`FEATURE_TOP_PORTS);
    smart_terminal_hw_top #(.FEATURE_MASK(5'h02)) u_top (`FEATURE_TOP_CONNECTIONS);
endmodule

module smart_terminal_realtime_top (`FEATURE_TOP_PORTS);
    smart_terminal_hw_top #(.FEATURE_MASK(5'h04)) u_top (`FEATURE_TOP_CONNECTIONS);
endmodule

module smart_terminal_audio_viz_top (`FEATURE_TOP_PORTS);
    smart_terminal_hw_top #(.FEATURE_MASK(5'h08)) u_top (`FEATURE_TOP_CONNECTIONS);
endmodule

module smart_terminal_scaling_top (`FEATURE_TOP_PORTS);
    smart_terminal_hw_top #(.FEATURE_MASK(5'h10)) u_top (`FEATURE_TOP_CONNECTIONS);
endmodule

module base_clock_pll_led_top (`FEATURE_TOP_PORTS);
    wire sd_card_clk;
    wire ext_mem_clk;
    wire ext_mem_clk_sft;
    wire video_clk;
    wire hdmi_5x_clk;
    wire audio_mclk;
    wire audio_pll_lock;

    reg [24:0] video_div;
    reg [24:0] hdmi_div;
    reg [24:0] audio_div;

    sys_pll u_sys_pll (
        .refclk   (clk),
        .clk0_out (sd_card_clk),
        .clk1_out (ext_mem_clk),
        .clk2_out (ext_mem_clk_sft),
        .reset    (1'b0)
    );

    video_pll u_video_pll (
        .refclk   (clk),
        .clk0_out (video_clk),
        .clk1_out (hdmi_5x_clk),
        .reset    (1'b0)
    );

    PLL_HDMI_AUDIO u_audio_pll (
        .refclk   (clk),
        .reset    (1'b0),
        .extlock  (audio_pll_lock),
        .clk0_out (),
        .clk1_out (),
        .clk2_out (audio_mclk)
    );

    always @(posedge video_clk or negedge rst_n) begin
        if (!rst_n)
            video_div <= 25'd0;
        else
            video_div <= video_div + 25'd1;
    end

    always @(posedge hdmi_5x_clk or negedge rst_n) begin
        if (!rst_n)
            hdmi_div <= 25'd0;
        else
            hdmi_div <= hdmi_div + 25'd1;
    end

    always @(posedge audio_mclk or negedge rst_n) begin
        if (!rst_n)
            audio_div <= 25'd0;
        else
            audio_div <= audio_div + 25'd1;
    end

    assign led[0] = audio_pll_lock;
    assign led[1] = video_div[24];
    assign led[2] = hdmi_div[24];
    assign led[3] = audio_div[24];

    assign seg_sel  = 6'b111111;
    assign seg_data = 8'hFF;

    assign HDMI_CLK_P   = 1'b0;
    assign HDMI_D2_P    = 1'b0;
    assign HDMI_D1_P    = 1'b0;
    assign HDMI_D0_P    = 1'b0;
    assign HDMI_DDC_SCL = 1'b1;
    assign HDMI_DDC_SDA = 1'bz;

    assign sd_ncs  = 1'b1;
    assign sd_dclk = 1'b0;
    assign sd_mosi = 1'b0;
endmodule

module base_rgb_hdmi_test_top (`FEATURE_TOP_PORTS);
    wire video_clk;
    wire hdmi_5x_clk;
    wire hs;
    wire vs;
    wire de;
    wire [11:0] x;
    wire [11:0] y;
    wire axis_user;
    wire axis_valid;
    wire axis_last;
    wire [23:0] axis_data;
    wire axis_ready;
    wire edid_trig;
    wire [9:0] ch0;
    wire [9:0] ch1;
    wire [9:0] ch2;
    wire [9:0] clk_tmds;
    wire [23:0] test_rgb;
    wire [11:0] ax = x - 12'd144;
    wire [11:0] ay = y - 12'd35;
    wire rst = ~rst_n;

    video_pll u_video_pll (
        .refclk   (clk),
        .clk0_out (video_clk),
        .clk1_out (hdmi_5x_clk),
        .reset    (1'b0)
    );

    video_timing_640x480 u_video_timing (
        .clk         (video_clk),
        .rst         (rst),
        .hs          (hs),
        .vs          (vs),
        .de          (de),
        .x           (x),
        .y           (y),
        .frame_start (),
        .frame_last  ()
    );

    assign test_rgb =
        (ay >= 12'd240) ?
            ((ax[7] ^ ay[7]) ? 24'h404040 : 24'hC0C0C0) :
        (ax < 12'd128)  ? 24'hFF0000 :
        (ax < 12'd256)  ? 24'h00FF00 :
        (ax < 12'd384)  ? 24'h0000FF :
        (ax < 12'd512)  ? 24'hFFFFFF :
                          24'h000000;

    video_rgb_to_axis_640x480 u_video_rgb_to_axis (
        .I_clk         (video_clk),
        .I_rst         (rst),
        .I_vs          (vs),
        .I_de          (de),
        .I_rgb         (test_rgb),
        .O_video_user  (axis_user),
        .O_video_valid (axis_valid),
        .O_video_last  (axis_last),
        .O_video_data  (axis_data)
    );

    startup_pulse #(.CNT_MAX(20'd100000)) u_startup_pulse (
        .I_clk   (video_clk),
        .I_rst   (rst),
        .O_pulse (edid_trig)
    );

    hdmi_1_4b_transmitter_core_wrapper #(
        .DEVICE            ("EG"),
        .HTOTAL            (800),
        .HSA               (96),
        .HFP               (16),
        .HBP               (48),
        .HACTIVE           (640),
        .VTOTAL            (525),
        .VSA               (2),
        .VFP               (10),
        .VBP               (33),
        .VACTIVE           (480),
        .VIDEO_VIC         (1),
        .VIDEO_TPG         ("Disable"),
        .VIDEO_FORMAT      ("RGB"),
        .AUDIO_SAMPLE_RATE ("48K"),
        .IIC_SCL_DIV       (250)
    ) u_hdmi (
        .I_pixel_clk        (video_clk),
        .I_rst              (rst),
        .I_edid_read_trig   (edid_trig),
        .O_edid_read_valid  (),
        .O_edid_read_data   (),
        .I_axis_s_user      (axis_user),
        .I_axis_s_valid     (axis_valid),
        .I_axis_s_last      (axis_last),
        .I_axis_s_data      (axis_data),
        .O_axis_s_ready     (axis_ready),
        .I_audio_valid      (1'b0),
        .I_audio_left_data  (24'd0),
        .I_audio_right_data (24'd0),
        .I_acr_valid        (1'b0),
        .I_acr_cts          (20'd0),
        .I_acr_n            (20'd0),
        .O_video_locked     (led[0]),
        .O_ddc_scl          (HDMI_DDC_SCL),
        .IO_ddc_sda         (HDMI_DDC_SDA),
        .O_ch0_tmds_data    (ch0),
        .O_ch1_tmds_data    (ch1),
        .O_ch2_tmds_data    (ch2),
        .O_clk_tmds_data    (clk_tmds)
    );

    hdmi_phy_wrapper #(.DEVICE("EG")) u_hdmi_phy (
        .I_pixel_clk        (video_clk),
        .I_serial_clk       (hdmi_5x_clk),
        .I_rst              (rst),
        .I_tmds_channel_0   (ch0),
        .I_tmds_channel_1   (ch1),
        .I_tmds_channel_2   (ch2),
        .I_tmds_channel_clk (clk_tmds),
        .O_tmds_ch0_p       (HDMI_D0_P),
        .O_tmds_ch1_p       (HDMI_D1_P),
        .O_tmds_ch2_p       (HDMI_D2_P),
        .O_tmds_clk_p       (HDMI_CLK_P)
    );

    assign led[1] = vs;
    assign led[2] = de;
    assign led[3] = axis_ready;
    assign seg_sel  = 6'b111111;
    assign seg_data = 8'hFF;
    assign sd_ncs  = 1'b1;
    assign sd_dclk = 1'b0;
    assign sd_mosi = 1'b0;
endmodule

`undef FEATURE_TOP_PORTS
`undef FEATURE_TOP_CONNECTIONS
