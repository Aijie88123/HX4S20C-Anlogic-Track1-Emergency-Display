`timescale 1ns/1ps

// Frequency-power bars, driven by the existing Goertzel analyzer.
// Mapping is performed on band updates; the pixel path selects an 8-bit height.
// Only complete band sets are displayed, and only at the vblank frame tick.
// Rise and fall both follow the newest complete analysis window at vblank.
// A separate collection bank prevents partial windows leaking into the display.
// Pitch detail uses a monotonic segmented power curve and an atomic raw-power
// winner marker; legacy parameters retain the old calibration and pixel timing.
module audio_spectrum_overlay #(
    parameter integer SCREEN_W = 1280,
    parameter integer SCREEN_H = 720,
    // Eight bars at 16 pixels pitch, implemented using bit selection.
    parameter integer BAR_W = 128,
    parameter integer BAR_H = 100,
    parameter integer BAR_X = SCREEN_W - BAR_W - 44,
    parameter integer BAR_Y = SCREEN_H - 100 - 76,
    parameter integer N_BANDS = 8,
    // Production 160-pixel panel scales the original calibrated height by
    // 13/8 using shifts/adds. Default preserves the legacy 100-pixel panel.
    parameter integer HEIGHT_SCALE_13_8 = 0,
    parameter integer PITCH_DETAIL = 0,
    parameter integer EXTERNAL_SOURCE = 0
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        frame_tick,

    // 来自 audio_fft 的频带功率
    input  wire        band_valid,
    input  wire [4:0]  band_idx,
    input  wire [15:0] band_mag,
    input wire source_live,

    input  wire [11:0] x,
    input  wire [11:0] y,

    output reg  [23:0] bars_rgb,
    output reg  [7:0]  bars_alpha
);

    localparam integer BAR_LEFT   = BAR_X;
    localparam integer BAR_RIGHT  = BAR_X + BAR_W - 1;
    localparam integer BAR_TOP    = BAR_Y;
    localparam integer BAR_BOTTOM = BAR_Y + BAR_H - 1;
    // Supported panel geometries: eight at 16-pixel pitch, twelve at 32.
    localparam integer BAR_PITCH = BAR_W / N_BANDS;
    localparam integer PITCH_SHIFT = (BAR_PITCH == 32) ? 5 : 4;
    localparam integer BAR_WIDTH = BAR_PITCH * 5 / 8;
    localparam [9:0] LEVEL_MAX = BAR_H - 6;   // 最响时柱子顶到面板上沿

    // Convert power to 8-bit pixel height on the slow FFT update path.
    // Collect a complete band set, then change display heights only in vblank.
    // No artificial release tail: a frequency change must extinguish its old
    // bar as promptly as the new one rises. FFT windowing already smooths PCM.
    reg [7:0] collecting_level [0:N_BANDS-1];
    reg [7:0] pending_level [0:N_BANDS-1];
    reg [7:0] display_level [0:N_BANDS-1];
    reg [N_BANDS-1:0] received_bands;
    reg pending_complete;
    reg [1:0] idle_frames;
    reg [15:0] collecting_peak_mag;
    reg [4:0] collecting_peak_idx, pending_peak_idx, display_peak_idx;
    reg pending_peak_valid, display_peak_valid;
    wire valid_band = band_valid && (band_idx < N_BANDS);
    wire [N_BANDS-1:0] incoming_mask = {{(N_BANDS-1){1'b0}},1'b1} << band_idx;
    wire [9:0] incoming_low = {1'b0,band_mag[15:7]};
    wire [9:0] incoming_high = {3'b000,band_mag[15:9]} + 10'd20;
    wire [9:0] incoming_raw = incoming_low < incoming_high ? incoming_low : incoming_high;
    wire [7:0] calibrated_level = incoming_raw > 10'd94 ? 8'd94 : incoming_raw[7:0];
    wire [11:0] expanded_level = ({4'd0,calibrated_level} << 3) +
                                 ({4'd0,calibrated_level} << 2) +
                                 {4'd0,calibrated_level};
    wire [9:0] scaled_level = HEIGHT_SCALE_13_8 ? expanded_level[11:3] : {2'd0,calibrated_level};
    // Continuous segments over the full 16-bit power range. The 256 floor
    // suppresses tiny sidelobes; 16/40/88/120 are the segment join heights.
    // This slow band-update path needs only bit slices and constant adds.
    function [7:0] detail_height;
        input [15:0] power;
        begin
            if(power[15]) detail_height = 8'd88 + {2'd0,power[15:10]};
            else if(power[14]) detail_height = 8'd56 + {2'd0,power[14:9]};
            else if(|power[13:12]) detail_height = 8'd24 + {2'd0,power[13:8]};
            else if(|power[11:10]) detail_height = 8'd8 + {3'd0,power[11:7]};
            else if(|power[9:8]) detail_height = {4'd0,power[9:6]};
            else detail_height = 8'd0;
        end
    endfunction
    wire [9:0] mapped_level = PITCH_DETAIL ? {2'd0,detail_height(band_mag)} : scaled_level;
    wire [7:0] incoming_level = mapped_level > LEVEL_MAX ? LEVEL_MAX[7:0] : mapped_level[7:0];
    wire incoming_wins = (band_idx == 0) || (band_mag > collecting_peak_mag);
    wire [4:0] complete_peak_idx = incoming_wins ? band_idx : collecting_peak_idx;
    wire complete_peak_valid = (incoming_wins ? band_mag : collecting_peak_mag) >= 16'd256;
    wire set_complete = valid_band &&
                        ((band_idx == 0) ? (N_BANDS == 1) :
                         &(received_bands | incoming_mask));
    wire [7:0] target_level [0:N_BANDS-1];
    genvar g;
    generate for(g=0;g<N_BANDS;g=g+1)begin: envelope_per_band
        // Include a set finishing on the vblank edge, avoiding an extra frame.
        assign target_level[g] = set_complete ?
                                  ((band_idx == g) ? incoming_level : collecting_level[g]) :
                                  ((pending_complete && idle_frames < 2) ? pending_level[g] : 8'd0);
    end endgenerate

    integer i;

    always @(posedge clk) begin
        if (rst || (EXTERNAL_SOURCE && !source_live)) begin
            for (i = 0; i < N_BANDS; i = i + 1)begin
                collecting_level[i] <= 8'd0;
                pending_level[i] <= 8'd0;
                display_level[i] <= 8'd0;
            end
            received_bands <= {N_BANDS{1'b0}};
            pending_complete <= 1'b0;
            idle_frames <= 2'd0;
            collecting_peak_mag <= 16'd0;
            collecting_peak_idx <= 5'd0;
            pending_peak_idx <= 5'd0;
            display_peak_idx <= 5'd0;
            pending_peak_valid <= 1'b0;
            display_peak_valid <= 1'b0;
        end
        else begin
            if(frame_tick)begin
                if(idle_frames != 2'd3)idle_frames <= idle_frames + 2'd1;
                for(i=0;i<N_BANDS;i=i+1)
                    display_level[i] <= target_level[i];
                if(PITCH_DETAIL)begin
                    display_peak_idx <= set_complete ? complete_peak_idx : pending_peak_idx;
                    display_peak_valid <= set_complete ? complete_peak_valid :
                        (pending_complete && idle_frames < 2 && pending_peak_valid);
                end
            end
            if(valid_band)begin
                if(PITCH_DETAIL && incoming_wins)begin
                    collecting_peak_mag <= band_mag;
                    collecting_peak_idx <= band_idx;
                end
                collecting_level[band_idx] <= incoming_level;
                if(band_idx==0)begin
                    received_bands <= incoming_mask;
                end else begin
                    received_bands <= received_bands | incoming_mask;
                end
                if(set_complete)begin
                    for(i=0;i<N_BANDS;i=i+1)
                        pending_level[i] <= (band_idx == i) ? incoming_level : collecting_level[i];
                    pending_complete <= 1'b1;
                    idle_frames <= 2'd0;
                    if(PITCH_DETAIL)begin
                        pending_peak_idx <= complete_peak_idx;
                        pending_peak_valid <= complete_peak_valid;
                    end
                end
            end
        end
    end

    // ---- 显示侧第一级：同步读出本像素所在柱子的幅度 ----
    // (x - BAR_LEFT) 在区域外会回绕，但那时 in_region 为假、输出被屏蔽，
    // 所以不需要额外的边界保护。BAR_PITCH = 16，[7:4] 就是 /16。
    wire [11:0] dx = x - BAR_LEFT;
    wire [4:0] display_band = dx >> PITCH_SHIFT;

    reg [11:0] x_d;
    reg [11:0] y_d;
    reg [7:0] level_d;
    reg peak_d;

    always @(posedge clk) begin
        if (rst) begin
            x_d   <= 12'd0;
            y_d   <= 12'd0;
            level_d <= 8'd0;
            peak_d <= 1'b0;
        end
        else begin
            x_d   <= x;
            y_d   <= y;
            level_d <= (display_band < N_BANDS) ? display_level[display_band] : 8'd0;
            peak_d <= PITCH_DETAIL && display_peak_valid && (display_band == display_peak_idx);
        end
    end

    // ---- 显示侧第二级：由寄存后的值生成像素 ----
    wire [11:0] dx_d = x_d - BAR_LEFT;
    wire [11:0] dy_d = y_d - BAR_TOP;

    wire in_region = (x_d >= BAR_LEFT) && (x_d <= BAR_RIGHT) &&
                     (y_d >= BAR_TOP)  && (y_d <= BAR_BOTTOM);

    // Mapping is computed on band arrival, outside the pixel pipeline.
    wire [9:0]  level = {2'b00,level_d};
    wire [10:0] bar_h   = 11'd6 + {1'b0, level};
    wire [10:0] bar_top = BAR_BOTTOM - bar_h;

    wire bar_fill = in_region && (y_d >= bar_top) &&
                    ((dx_d & (BAR_PITCH - 1)) < BAR_WIDTH);
    // Two white pixels at the winner's top edge. Register peak_d with level_d
    // so marker, body and coordinates all have the same pixel latency.
    wire peak_mark = bar_fill && peak_d && (y_d < bar_top + 11'd2);

    wire bar_frame = in_region &&
                     ((dx_d < 3) ||
                      (dx_d >= (BAR_W - 3)) ||
                      (dy_d < 3) ||
                      (dy_d >= (BAR_H - 3)));

    // Eight distinct bright colors; the old 16-bin gradient only covered its
    // blue/green half when used with eight bands.
    function [23:0] band_color;
        input [3:0] index;
        begin
            case(index)
                0: band_color = 24'h28C7FA;
                1: band_color = 24'h30D98B;
                2: band_color = 24'hF2C94C;
                3: band_color = 24'hF2994A;
                4: band_color = 24'hEB5757;
                5: band_color = 24'hBB6BD9;
                6: band_color = 24'h2D9CDB;
                7: band_color = 24'h56CCF2;
                8: band_color = 24'hFF709D;
                9: band_color = 24'hA8E85C;
                10: band_color = 24'hFFA638;
                11: band_color = 24'hD28BFF;
                default: band_color = 24'h28C7FA;
            endcase
        end
    endfunction
    wire [23:0] bar_col = band_color(dx_d >> PITCH_SHIFT);

    wire [11:0] label_x=x_d-(BAR_LEFT+8);
    wire [11:0] label_y=y_d-(BAR_TOP+7);
    reg [7:0] label_char;
    reg [4:0] glyph_row;
    always @* begin
        case(label_x[5:3])
            0:label_char="B";1:label_char=":";2:label_char="O";
            3:label_char=source_live?"N":"F";4:label_char=source_live?" ":"F";
            default:label_char=" ";
        endcase
        glyph_row=0;
        case(label_char)
            "B":case(label_y[2:0])
                0,3,6:glyph_row=5'b11110;
                1,2,4,5:glyph_row=5'b10001;
            endcase
            ":":if(label_y[2:0]==2 || label_y[2:0]==4)glyph_row=5'b00100;
            "O":case(label_y[2:0])
                0,6:glyph_row=5'b01110;
                1,2,3,4,5:glyph_row=5'b10001;
            endcase
            "N":case(label_y[2:0])
                0,1,5,6:glyph_row=5'b10001;
                2:glyph_row=5'b11001;3:glyph_row=5'b10101;4:glyph_row=5'b10011;
            endcase
            "F":case(label_y[2:0])
                0:glyph_row=5'b11111;3:glyph_row=5'b11110;
                1,2,4,5,6:glyph_row=5'b10000;
            endcase
        endcase
    end
    wire legend=EXTERNAL_SOURCE && label_x<40 && label_y<7 &&
        label_x[2:0]<5 && glyph_row[4-label_x[2:0]];
    always @(*) begin
        if(legend)begin
            bars_rgb=source_live?24'h76E4B0:24'hFFC16E;bars_alpha=255;
        end else if (peak_mark) begin
            bars_rgb = 24'hFFFFFF;
            bars_alpha = 8'd255;
        end
        else if (bar_fill) begin
            bars_rgb   = bar_col;
            bars_alpha = 8'd255;
        end
        else if (bar_frame) begin
            bars_rgb   = (EXTERNAL_SOURCE && !source_live) ? 24'hDB7D2C : 24'h2E6FA8;
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
