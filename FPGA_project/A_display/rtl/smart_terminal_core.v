`timescale 1ns/1ps

module smart_terminal_core #(
    parameter integer H_ACTIVE = 640,
    parameter integer H_FRONT  = 16,
    parameter integer H_SYNC   = 96,
    parameter integer H_BACK   = 48,
    parameter integer V_ACTIVE = 480,
    parameter integer V_FRONT  = 10,
    parameter integer V_SYNC   = 2,
    parameter integer V_BACK   = 33,
    parameter integer SRC_W    = 320,
    parameter integer SRC_H    = 240,
    parameter [3:0] FEATURE_MASK = 4'hF
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        emergency,
    input  wire [1:0]  page_index,
    input  wire [2:0]  brightness,
    input  wire [2:0]  contrast,

    output wire        video_hs,
    output wire        video_vs,
    output wire        video_de,
    output wire        video_user,
    output wire        video_last,
    output wire [23:0] video_rgb,
    output wire        frame_ready,

    output wire        i2s_bclk,
    output wire        i2s_lrck,
    output wire        i2s_dout,
    output wire        audio_sample_valid,
    output wire [15:0] audio_magnitude,
    output wire [23:0] audio_left_debug
);

    localparam integer PIXELS  = H_ACTIVE * V_ACTIVE;
    localparam integer ADDR_W  = $clog2(PIXELS);
    localparam integer H_START = H_SYNC + H_BACK;
    localparam integer V_START = V_SYNC + V_BACK;

    wire        timing_hs;
    wire        timing_vs;
    wire        timing_de;
    wire [11:0] timing_x;
    wire [11:0] timing_y;
    wire        timing_frame_start;
    wire        timing_frame_last;

    wire        source_valid;
    wire [23:0] source_rgb;
    wire        source_line_last;
    wire [15:0] source_x;
    wire [15:0] source_y;
    wire [15:0] source_frame_id;
    wire        source_ready;

    wire        scaler_valid;
    wire [23:0] scaler_rgb;
    wire        scaler_line_last;
    wire        scaler_ready;

    reg [ADDR_W-1:0] write_pixel;
    reg              write_commit;

    reg        display_hs;
    reg        display_vs;
    reg        display_de;
    reg [11:0] display_x;
    reg [11:0] display_y;
    reg [23:0] base_rgb;
    reg        frame_gate;
    wire [ADDR_W-1:0] read_addr;

    wire [23:0] frame_rgb;
    wire        frame_buffer_ready;
    wire        write_bank;
    wire [11:0] active_x = timing_x - H_START;
    wire [11:0] active_y = timing_y - V_START;

    wire        overlay_hs;
    wire        overlay_vs;
    wire        overlay_de;
    wire [23:0] overlay_rgb;
    wire [11:0] overlay_x;
    wire [11:0] overlay_y;

    wire        i2s_left_valid;
    wire [23:0] i2s_left_data;
    wire [23:0] i2s_right_data;
    wire [23:0] tone_sample_debug;

    video_timing_640x480 #(
        .H_ACTIVE (H_ACTIVE),
        .H_FRONT  (H_FRONT),
        .H_SYNC   (H_SYNC),
        .H_BACK   (H_BACK),
        .V_ACTIVE (V_ACTIVE),
        .V_FRONT  (V_FRONT),
        .V_SYNC   (V_SYNC),
        .V_BACK   (V_BACK)
    ) u_video_timing (
        .clk         (clk),
        .rst         (rst),
        .hs          (timing_hs),
        .vs          (timing_vs),
        .de          (timing_de),
        .x           (timing_x),
        .y           (timing_y),
        .frame_start (timing_frame_start),
        .frame_last  (timing_frame_last)
    );

    frame_pattern_source #(
        .WIDTH  (SRC_W),
        .HEIGHT (SRC_H)
    ) u_frame_pattern_source (
        .clk           (clk),
        .rst           (rst),
        .out_ready     (source_ready),
        .out_valid     (source_valid),
        .out_rgb       (source_rgb),
        .out_line_last (source_line_last),
        .out_x         (source_x),
        .out_y         (source_y),
        .frame_id      (source_frame_id)
    );

    area_scaler_2x #(
        .IN_WIDTH  (SRC_W),
        .OUT_WIDTH (H_ACTIVE)
    ) u_area_scaler_2x (
        .clk           (clk),
        .rst           (rst),
        .in_valid      (source_valid),
        .in_rgb        (source_rgb),
        .in_line_last  (source_line_last),
        .in_ready      (source_ready),
        .out_valid     (scaler_valid),
        .out_rgb       (scaler_rgb),
        .out_line_last (scaler_line_last)
    );

    always @(posedge clk) begin
        if (rst) begin
            write_pixel  <= {ADDR_W{1'b0}};
            write_commit <= 1'b0;
        end
        else begin
            write_commit <= 1'b0;

            if (scaler_valid) begin
                if (write_pixel == PIXELS - 1) begin
                    write_pixel  <= {ADDR_W{1'b0}};
                    write_commit <= 1'b1;
                end
                else begin
                    write_pixel <= write_pixel + 1'b1;
                end
            end
        end
    end

    frame_buffer_pingpong #(
        .PIXELS (PIXELS),
        .ADDR_W (ADDR_W)
    ) u_frame_buffer_pingpong (
        .wr_clk     (clk),
        .rst        (rst),
        .wr_en      (scaler_valid),
        .wr_addr    (write_pixel),
        .wr_data    (scaler_rgb),
        .wr_commit  (write_commit),
        .rd_clk     (clk),
        .rd_en      (timing_de),
        .rd_addr    (read_addr),
        .rd_data    (frame_rgb),
        .frame_ready(frame_buffer_ready),
        .write_bank (write_bank)
    );

    always @(posedge clk) begin
        if (rst) begin
            display_hs <= 1'b0;
            display_vs <= 1'b0;
            display_de <= 1'b0;
            display_x  <= 12'd0;
            display_y  <= 12'd0;
            base_rgb   <= 24'd0;
            frame_gate <= 1'b0;
        end
        else begin
            display_hs <= timing_hs;
            display_vs <= timing_vs;
            display_de <= timing_de;

            if (timing_de) begin
                display_x <= active_x;
                display_y <= active_y;
                base_rgb  <= frame_rgb;
            end

            if (frame_buffer_ready && !timing_de &&
                ((timing_y < V_START) ||
                 (timing_y >= (V_START + V_ACTIVE))))
                frame_gate <= 1'b1;
        end
    end

    tone_i2s_64fs #(
        .MCLK_HZ        (25_200_000),
        .SAMPLE_RATE_HZ (48_000),
        .TONE_HZ        (1_000)
    ) u_tone_i2s_64fs (
        .clk          (clk),
        .rst          (rst),
        .bclk         (i2s_bclk),
        .lrck         (i2s_lrck),
        .dout         (i2s_dout),
        .sample_debug (tone_sample_debug)
    );

    assign read_addr = (active_y * H_ACTIVE) + active_x;

    i2s_receiver_24 u_i2s_receiver_24 (
        .clk         (clk),
        .rst         (rst),
        .i2s_bclk    (i2s_bclk),
        .i2s_lrck    (i2s_lrck),
        .i2s_dout    (i2s_dout),
        .audio_valid (i2s_left_valid),
        .audio_left  (i2s_left_data),
        .audio_right (i2s_right_data)
    );

    audio_envelope u_audio_envelope (
        .clk          (clk),
        .rst          (rst),
        .sample_valid (i2s_left_valid),
        .sample_left  (i2s_left_data),
        .magnitude    (audio_magnitude)
    );

    smart_terminal_overlay_pipelined #(
        .SCREEN_W (H_ACTIVE),
        .SCREEN_H (V_ACTIVE),
        // 这条仿真核用**滑动擦除**而不是淡入淡出：
        // 淡出是靠 sd_card_bmp 的 write_buf_idx/disp_buf_idx 差值触发的，而本核
        // 没有那条双缓冲载图链路，load_in_flight 只能恒 0 —— 选淡入淡出的话
        // 转场层永远不动，tb_smart_terminal_core 的"转场可见"检查会拿到 0 像素。
        // 上板用的是 smart_terminal_hw_top（TRANSITION_MODE 默认 0 = 淡入淡出），
        // 那条路径由 tb_transition_fade 专项覆盖。
        .TRANSITION_MODE (1)
    ) u_smart_terminal_overlay (
        .clk       (clk),
        .rst       (rst),
        .i_hs      (display_hs),
        .i_vs      (display_vs),
        .i_de      (display_de && frame_gate),
        .i_rgb     (base_rgb),
        .emergency (emergency),
        // 本仿真核里没有 sd_card_bmp 的双缓冲索引，转场按「无载图」处理。
        // 淡入淡出的时序由 tb_overlay_pipelined 与上板验收负责覆盖。
        .load_in_flight (1'b0),
        .fx_sel    (3'd0),
        .fx_off    (1'b0),
        .audio_mag (audio_magnitude),
        .audio_sample_valid (i2s_left_valid),
        .audio_sample       (i2s_left_data),
        // 该仿真核只用 0/1 两页，显式零扩展到 3 bit（叠加层已按 5 张图加宽）
        .page_index({1'b0, page_index}),
        .brightness(brightness),
        .contrast  (contrast),
        .feature_mask(FEATURE_MASK),
        // 本仿真核没有 SD 链路，画面来自内部图案源（640x480），
        // 所以信息栏上的源分辨率就按这个写实值接。
        .src_w     (16'd640),
        .src_h     (16'd480),
        .o_hs      (overlay_hs),
        .o_vs      (overlay_vs),
        .o_de      (overlay_de),
        .o_rgb     (overlay_rgb),
        .o_x       (overlay_x),
        .o_y       (overlay_y)
    );

    assign video_hs   = overlay_hs;
    assign video_vs   = overlay_vs;
    assign video_de   = overlay_de;
    assign video_rgb  = overlay_rgb;
    assign frame_ready = frame_buffer_ready;

    assign video_user = overlay_de && (overlay_x == 0) && (overlay_y == 0);
    assign video_last = overlay_de && (overlay_x == H_ACTIVE - 1) &&
                        (overlay_y == V_ACTIVE - 1);

    assign audio_sample_valid = i2s_left_valid;
    assign audio_left_debug   = i2s_left_data;

endmodule
