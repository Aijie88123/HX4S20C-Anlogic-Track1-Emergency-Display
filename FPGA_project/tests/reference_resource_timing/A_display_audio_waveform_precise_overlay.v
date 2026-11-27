// Actual PCM,192 ten-bit points in production; fixed x4 vertical scale.
// Two complete capture pages; positive-up trace, zero-cross trigger,12ms grid.
module audio_waveform_precise_overlay #(
    parameter integer SCREEN_W = 1280,
    parameter integer SCREEN_H = 720,
    
    parameter integer WAVE_W = 256,
    parameter integer WAVE_H = 180,
    parameter integer WAVE_X = 40,
    parameter integer WAVE_Y = 150,

    parameter integer POINT_PX = 4,
    
    parameter integer SAMPLE_STEP = 5
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        frame_tick,        
    input  wire        audio_sample_valid,
    input  wire [23:0] audio_sample,
    input  wire [11:0] x,
    input  wire [11:0] y,

    output reg  [23:0] wave_rgb,
    output reg  [7:0]  wave_alpha
);

    localparam integer WAVE_LEFT   = WAVE_X;
    localparam integer WAVE_RIGHT  = WAVE_X + WAVE_W - 1;
    localparam integer WAVE_TOP    = WAVE_Y;
    localparam integer WAVE_BOTTOM = WAVE_Y + WAVE_H - 1;
    localparam integer WAVE_CENTER = (WAVE_TOP + WAVE_BOTTOM) / 2;
    localparam integer TRACE_HALF  = 1;      

    localparam integer N_POINTS    = WAVE_W / POINT_PX;

    localparam integer PX_SHIFT    = $clog2(POINT_PX);   
    localparam integer IDX_W       = $clog2(N_POINTS);   

    (* ram_style="bram" *) reg [9:0] cap_ram [0:511];
    reg        cap_wr_page;
    reg        cap_rd_page;
    reg        cap_ready_page;
    reg        cap_ready_valid;
    reg        cap_display_valid;
    reg [IDX_W-1:0] cap_ptr;
    reg [3:0]  cap_step;
    reg [1:0]  cap_state;
    reg        cap_prev_sign;
    reg [19:0] cap_timeout;

    localparam integer ST_WAIT_FRAME = 2'd0;
    localparam integer ST_WAIT_ZERO  = 2'd1;
    localparam integer ST_CAPTURE    = 2'd2;

    localparam integer ZERO_TIMEOUT  = 700000;

    wire cap_zero_cross = cap_prev_sign && !audio_sample[23];
    wire cap_last_point = (cap_step == (SAMPLE_STEP - 1));

    wire [9:0] capture_sample = !audio_sample[23] && (|audio_sample[22:21]) ? 10'h1ff :
                                audio_sample[23] && (audio_sample[22:21] != 2'b11) ? 10'h200 :
                                audio_sample[21:12];
    always @(posedge clk) begin
        if (rst) begin
            cap_wr_page    <= 1'b1;
            cap_rd_page    <= 1'b0;
            cap_ready_page <= 1'b0;
            cap_ptr        <= 6'd0;
            cap_step       <= 4'd0;
            cap_state      <= ST_WAIT_FRAME;
            cap_prev_sign  <= 1'b0;
            cap_timeout    <= 20'd0;
            cap_ready_valid <= 1'b0;
            cap_display_valid <= 1'b0;
        end
        else begin
            if (audio_sample_valid)
                cap_prev_sign <= audio_sample[23];

            case (cap_state)
                ST_WAIT_FRAME: begin
                    if (frame_tick) begin
                        cap_rd_page <= cap_ready_page;
                        cap_display_valid <= cap_ready_valid;
                        cap_state  <= ST_WAIT_ZERO;
                        cap_timeout <= 20'd0;
                    end
                end

                ST_WAIT_ZERO: begin
                    cap_timeout <= cap_timeout + 20'd1;
                    if (audio_sample_valid && cap_zero_cross) begin
                        cap_state <= ST_CAPTURE;
                        cap_ptr   <= 6'd0;
                        cap_step  <= 4'd0;
                    end
                    else if (cap_timeout >= ZERO_TIMEOUT) begin
                        cap_state <= ST_CAPTURE;
                        cap_ptr   <= 6'd0;
                        cap_step  <= 4'd0;
                    end
                end

                ST_CAPTURE: begin
                    if (audio_sample_valid) begin
                        if (cap_last_point) begin
                            cap_step <= 4'd0;
                            cap_ram[{cap_wr_page, cap_ptr}] <=
                                capture_sample;

                            if (cap_ptr == (N_POINTS - 1)) begin
                                cap_ready_page <= cap_wr_page;
                                cap_ready_valid <= 1'b1;
                                cap_wr_page    <= ~cap_wr_page;
                                cap_state      <= ST_WAIT_FRAME;
                            end
                            else begin
                                cap_ptr <= cap_ptr + 6'd1;
                            end
                        end
                        else begin
                            cap_step <= cap_step + 4'd1;
                        end
                    end
                end

                default: cap_state <= ST_WAIT_FRAME;
            endcase
        end
    end

    reg [11:0] x_d;
    reg [11:0] y_d;
    reg [9:0] sample_d;
    reg [11:0] x_d2;
    reg [11:0] y_d2;
    reg [7:0]  offset_d;
    reg        sign_d;
    reg [11:0] trace_low_d2,trace_high_d2;

    wire [IDX_W-1:0] sample_index = (x - WAVE_LEFT) >> PX_SHIFT;
    wire [IDX_W:0]   cap_rd_addr  = {cap_rd_page, sample_index};
    always @(posedge clk)sample_d<=cap_ram[cap_rd_addr];

    always @(posedge clk) begin
        if (rst) begin
            x_d      <= 12'd0;
            y_d      <= 12'd0;

            x_d2     <= 12'd0;
            y_d2     <= 12'd0;
            offset_d <= 8'd0;
            sign_d   <= 1'b0;
            trace_low_d2<=0;trace_high_d2<=0;
        end
        else begin
            x_d      <= x;
            y_d      <= y;

            sign_d   <= sample_d[9];
            offset_d <= sample_d[9] ? ((~sample_d + 10'd1) >> 3)
                                    : (sample_d >> 3);
            x_d2     <= x_d;
            y_d2     <= y_d;
            trace_low_d2<=y_d-TRACE_HALF;trace_high_d2<=y_d+TRACE_HALF;
        end
    end

    wire in_region = (x_d2 >= WAVE_LEFT) && (x_d2 <= WAVE_RIGHT) &&
                     (y_d2 >= WAVE_TOP)  && (y_d2 <= WAVE_BOTTOM);

    wire [11:0] raw_wave_y = sign_d ?
                         (WAVE_CENTER + {4'b0, offset_d}) :
                         (WAVE_CENTER - {4'b0, offset_d});
    reg [11:0] raw_wave_y_r;
    wire [12:0] midpoint={1'b0,raw_wave_y}+{1'b0,raw_wave_y_r};
    wire [11:0] wave_y=(POINT_PX==2 && !x_d2[0] && x_d2>WAVE_LEFT)?midpoint[12:1]:raw_wave_y;
    always @(posedge clk)if(rst)raw_wave_y_r<=WAVE_CENTER;else raw_wave_y_r<=raw_wave_y;

    reg [11:0] wave_y_r;

    always @(posedge clk) begin
        if (rst) wave_y_r <= WAVE_CENTER[11:0];
        else     wave_y_r <= wave_y;
    end

    wire        conn_on = in_region && (x_d2 > WAVE_LEFT) &&
                          (((y_d2 >= wave_y) && (y_d2 <= wave_y_r)) ||
                           ((y_d2 >= wave_y_r) && (y_d2 <= wave_y)));

    wire axis_on = in_region && ((y_d2 == WAVE_CENTER) ||
                                 (y_d2 == (WAVE_CENTER + 12'd1)));
    wire trace_on = in_region &&
                    (wave_y >= trace_low_d2) && (wave_y <= trace_high_d2);
    
    wire trace_px = cap_display_valid && (trace_on || conn_on);
    wire [11:0] panel_dx=x_d2-WAVE_LEFT,panel_dy=y_d2-WAVE_TOP;
    wire grid_on=in_region && ((panel_dx[4:0]==0)||(panel_dy[4:0]==0));

    wire [11:0] text_x=x-WAVE_LEFT-8,text_y=y-WAVE_TOP-7;
    reg [7:0] text_character;
    always @*case(text_x[6:3])
     0:text_character="P";1:text_character="C";2:text_character="M";
     4:text_character="1";5:text_character="2";6:text_character="m";7:text_character="s";
     9:text_character="x";10:text_character="4";
     default:text_character=" ";endcase
    wire [4:0] text_pixels;
    audio_label_font_fast u_wave_label(.character(text_character),.row(text_y[2:0]),.pixels(text_pixels));
    wire [4:0] glyph=text_pixels;
    reg text_on,text_range_d;reg [4:0] glyph_d;reg [2:0] glyph_column_d;
    always @(posedge clk)begin
     glyph_d<=glyph;glyph_column_d<=text_x[2:0];
     text_range_d<=!rst&&text_x<88&&text_y<7&&text_x[2:0]<5;
     text_on<=!rst&&text_range_d&&glyph_d[4-glyph_column_d];
    end
    wire frame_on = in_region &&
                    (((x_d2 - WAVE_LEFT) < 3) ||
                     ((x_d2 - WAVE_LEFT) >= (WAVE_W - 3)) ||
                     ((y_d2 - WAVE_TOP) < 3) ||
                     ((y_d2 - WAVE_TOP) >= (WAVE_H - 3)));

    always @(*) begin
        if(text_on)begin
            wave_rgb=24'hA9E7FF;wave_alpha=255;
        end else if (trace_px) begin
            wave_rgb   = 24'h6CFFB0;
            wave_alpha = 8'd255;
        end
        else if (frame_on) begin
            wave_rgb   = 24'h2E6FA8;
            wave_alpha = 8'd230;
        end
        else if (axis_on) begin
            wave_rgb   = 24'h54819F;
            wave_alpha = 8'd140;
        end
        else if(grid_on)begin
            wave_rgb=24'h173D50;wave_alpha=160;
        end
        else if (in_region) begin
            
            wave_rgb   = 24'h061420;
            wave_alpha = 8'd150;
        end
        else begin
            wave_rgb   = 24'h000000;
            wave_alpha = 8'd0;
        end
    end

endmodule
