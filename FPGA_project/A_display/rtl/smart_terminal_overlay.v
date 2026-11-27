`timescale 1ns/1ps

// Exact colour LUT decomposition, 8 contrast levels x 16 entries per part.
// v=16*h+l; floor((v-128)*(c+4)/8)=(h-8)*2*(c+4)+floor(l*(c+4)/8).
// Small asynchronous tables preserve the released pixel latency. No runtime
// multiply and no extra clock/PLL are needed; signed values precede saturation.
module video_enhance (
 input wire [23:0] in_rgb,input wire [2:0] brightness,contrast,
 output wire [23:0] out_rgb
);
 (* rom_style="distributed" *) reg [8:0] colour_coarse_lut[0:127];
 (* rom_style="distributed" *) reg [4:0] colour_fine_lut[0:127];
 integer c,v;
 initial begin
  for(c=0;c<8;c=c+1)for(v=0;v<16;v=v+1)begin
   colour_coarse_lut[c*16+v]=(v-8)*2*(c+4);
   colour_fine_lut[c*16+v]=(v*(c+4))/8;
  end
 end
 // Fold centre 128 into brightness bias: coarse range -176..154 fits nine bits.
 reg [7:0] bias;
 always @* case(brightness)
  0:bias=8'd80;1:bias=8'd92;2:bias=8'd104;3:bias=8'd116;
  4:bias=8'd128;5:bias=8'd140;6:bias=8'd152;default:bias=8'd164;
 endcase
 function [7:0] clipped;
  input signed [8:0] coarse;input [4:0] fine;input [7:0] offset;
  reg signed [9:0] adjusted;
  begin
   adjusted=coarse+$signed({1'b0,fine})+$signed({1'b0,offset});
   clipped=adjusted[9]?8'd0:(adjusted[8]?8'd255:adjusted[7:0]);
  end
 endfunction
 assign out_rgb[23:16]=clipped($signed(colour_coarse_lut[{contrast,in_rgb[23:20]}]),colour_fine_lut[{contrast,in_rgb[19:16]}],bias);
 assign out_rgb[15:8]=clipped($signed(colour_coarse_lut[{contrast,in_rgb[15:12]}]),colour_fine_lut[{contrast,in_rgb[11:8]}],bias);
 assign out_rgb[7:0]=clipped($signed(colour_coarse_lut[{contrast,in_rgb[7:4]}]),colour_fine_lut[{contrast,in_rgb[3:0]}],bias);
endmodule

// Algebraically identical final-stage blend; alpha no longer drives 255-alpha.
// base*(255-a)+layer*a = base*255+(layer-base)*a, with signed intermediate.
// The pixel interface remains combinational and cycle-aligned with the pipeline.
module alpha_blend_single_product(
 input wire [23:0] base_rgb,layer_rgb,input wire [7:0] alpha,
 output wire [23:0] out_rgb
);
 function [7:0] blended;
  input [7:0] base,layer,a;
  reg signed [8:0] delta;
  reg signed [17:0] weighted,base255,total;
  reg [16:0] mixed,corrected;
  begin
   delta=$signed({1'b0,layer})-$signed({1'b0,base});
   weighted=delta*$signed({1'b0,a});
   base255=($signed({1'b0,base})<<<8)-$signed({1'b0,base});
   total=base255+weighted;
   mixed=total[16:0];
   corrected=mixed+(mixed>>8)+17'd1;
   blended=corrected[15:8];
  end
 endfunction
 assign out_rgb[23:16]=blended(base_rgb[23:16],layer_rgb[23:16],alpha);
 assign out_rgb[15:8]=blended(base_rgb[15:8],layer_rgb[15:8],alpha);
 assign out_rgb[7:0]=blended(base_rgb[7:0],layer_rgb[7:0],alpha);
endmodule

module smart_terminal_overlay #(
    parameter integer SCREEN_W = 640,
    parameter integer SCREEN_H = 480
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        i_hs,
    input  wire        i_vs,
    input  wire        i_de,
    input  wire [23:0] i_rgb,
    input  wire        emergency,
    input  wire [15:0] audio_mag,
    input  wire        audio_sample_valid,
    input  wire [23:0] audio_sample,
    input  wire [1:0]  page_index,
    input  wire [2:0]  brightness,
    input  wire [2:0]  contrast,
    input  wire [3:0]  feature_mask,

    output reg         o_hs,
    output reg         o_vs,
    output reg         o_de,
    output reg  [23:0] o_rgb,
    output reg  [11:0] o_x,
    output reg  [11:0] o_y
);

    reg        de_d;
    reg        vs_d;
    reg        frame_tick;
    reg [11:0] x;
    reg [11:0] y;
    reg [1:0]  page_sync0;
    reg [1:0]  page_sync1;
    reg [1:0]  page_last;
    reg [11:0] scroll_phase;
    reg [6:0]  elapsed_seconds;
    reg [6:0]  second_divider;
    reg        transition_active;
    reg [11:0] transition_x;

    wire [23:0] text_rgb;
    wire [7:0]  text_alpha;
    wire [23:0] waveform_rgb;
    wire [7:0]  waveform_alpha;
    wire [23:0] bars_rgb;
    wire [7:0]  bars_alpha;
    wire [23:0] enhanced_base;
    wire [23:0] processed_base;
    wire [23:0] transition_mixed;
    wire [23:0] text_mixed;
    wire [23:0] bars_mixed;
    wire [23:0] wave_mixed;
    wire [15:0] active_audio_mag;
    wire        active_audio_valid;
    wire [7:0]  active_bars_alpha;
    wire [7:0]  active_wave_alpha;

    reg        p1_hs, p1_vs, p1_de;
    reg        p2_hs, p2_vs, p2_de;
    reg        p3_hs, p3_vs, p3_de;
    reg        p4_hs, p4_vs, p4_de;
    reg        p5_hs, p5_vs, p5_de;
    reg [11:0] p1_x, p1_y;
    reg [11:0] p2_x, p2_y;
    reg [11:0] p3_x, p3_y;
    reg [11:0] p4_x, p4_y;
    reg [11:0] p5_x, p5_y;
    reg [23:0] p1_rgb, p2_rgb, p3_rgb, p4_rgb, p5_rgb;
    reg [23:0] p3_text_rgb;
    reg [7:0]  p3_text_alpha;
    reg [23:0] p3_bars_rgb;
    reg [7:0]  p3_bars_alpha;
    reg [23:0] p3_wave_rgb;
    reg [7:0]  p3_wave_alpha;
    reg [23:0] p4_bars_rgb;
    reg [7:0]  p4_bars_alpha;
    reg [23:0] p4_wave_rgb;
    reg [7:0]  p4_wave_alpha;
    reg [23:0] p5_wave_rgb;
    reg [7:0]  p5_wave_alpha;

    localparam integer BANNER_CELL_N = 8 * 4;              // 与 text_overlay_8x8 的 BANNER_SCALE 一致
    localparam integer SCROLL_MAX = SCREEN_W + (15 * BANNER_CELL_N) - 1;
    localparam integer FRAMES_PER_SECOND = 60;

    wire transition_black = feature_mask[1] &&
                           transition_active && (p1_x < transition_x);
    wire transition_edge = feature_mask[1] &&
                           transition_active &&
                           (p1_x >= transition_x) &&
                           (p1_x < (transition_x + 12'd12));
    wire [23:0] transition_rgb = transition_edge ? 24'h00D8FF : 24'h000000;
    wire [7:0]  transition_alpha = transition_edge ? 8'd220 :
                                   (transition_black ? 8'd235 : 8'd0);

    video_enhance u_video_enhance (
        .in_rgb     (i_rgb),
        .brightness (brightness),
        .contrast   (contrast),
        .out_rgb    (enhanced_base)
    );

    assign processed_base = feature_mask[2] ? enhanced_base : i_rgb;

    alpha_blend u_transition_blend (
        .base_rgb  (p1_rgb),
        .layer_rgb (transition_rgb),
        .alpha     (transition_alpha),
        .out_rgb   (transition_mixed)
    );

    text_overlay_8x8 u_text_overlay (
        .clk             (clk),
        .rst             (rst),
        .emergency       (emergency),
        .blink_on        (1'b1),          // 仿真核心不做闪烁，警戒框常亮
        .x               (p2_x),
        .y               (p2_y),
        // 信息栏那一块在**早一拍**的坐标上译码（本模块的流水是 p1 -> p2）
        .x_pre           (p1_x),
        .y_pre           (p1_y),
        .page_index      (page_sync1),
        .brightness      (brightness),
        .contrast        (contrast),
        .elapsed_seconds (elapsed_seconds),
        .scroll_phase    (scroll_phase),
        .feature_mask    (feature_mask),
        .text_rgb        (text_rgb),
        .text_alpha      (text_alpha)
    );

    assign active_audio_mag   = feature_mask[3] ? audio_mag : 16'd0;
    assign active_audio_valid = feature_mask[3] && audio_sample_valid;
    assign active_bars_alpha  = feature_mask[3] ? bars_alpha : 8'd0;
    assign active_wave_alpha  = feature_mask[3] ? waveform_alpha : 8'd0;

    audio_bars_overlay #(
        .SCREEN_W (SCREEN_W),
        .SCREEN_H (SCREEN_H)
    ) u_audio_bars_overlay (
        .x          (p2_x),
        .y          (p2_y),
        .audio_mag  (active_audio_mag),
        .bars_rgb   (bars_rgb),
        .bars_alpha (bars_alpha)
    );

    audio_waveform_overlay #(
        .SCREEN_W (SCREEN_W),
        .SCREEN_H (SCREEN_H)
    ) u_audio_waveform_overlay (
        .clk                (clk),
        .rst                (rst),
        .frame_tick         (frame_tick),
        .audio_sample_valid (active_audio_valid),
        .audio_sample       (audio_sample),
        .x                  (p2_x),
        .y                  (p2_y),
        .wave_rgb           (waveform_rgb),
        .wave_alpha         (waveform_alpha)
    );

    alpha_blend u_text_blend_pipe (
        .base_rgb  (p3_rgb),
        .layer_rgb (p3_text_rgb),
        .alpha     (p3_text_alpha),
        .out_rgb   (text_mixed)
    );

    alpha_blend u_bars_blend_pipe (
        .base_rgb  (p4_rgb),
        .layer_rgb (p4_bars_rgb),
        .alpha     (p4_bars_alpha),
        .out_rgb   (bars_mixed)
    );

    alpha_blend u_wave_blend_pipe (
        .base_rgb  (p5_rgb),
        .layer_rgb (p5_wave_rgb),
        .alpha     (p5_wave_alpha),
        .out_rgb   (wave_mixed)
    );

    always @(posedge clk) begin
        if (rst) begin
            de_d <= 1'b0;
            vs_d <= 1'b1;
            x    <= 12'd0;
            y    <= 12'd0;
            page_sync0 <= 2'd0;
            page_sync1 <= 2'd0;
            page_last  <= 2'd0;
            scroll_phase <= 12'd0;
            elapsed_seconds <= 7'd0;
            second_divider <= 7'd0;
            transition_active <= 1'b0;
            transition_x <= 12'd0;
            frame_tick <= 1'b0;
        end
        else begin
            de_d <= i_de;
            vs_d <= i_vs;
            frame_tick <= (!i_vs && vs_d);
            page_sync0 <= page_index;
            page_sync1 <= page_sync0;

            if (!i_vs && vs_d) begin
                if (scroll_phase >= SCROLL_MAX)
                    scroll_phase <= 12'd0;
                else
                    scroll_phase <= scroll_phase + 12'd1;

                if (second_divider >= (FRAMES_PER_SECOND - 1)) begin
                    second_divider <= 7'd0;
                    if (elapsed_seconds == 7'd99)
                        elapsed_seconds <= 7'd0;
                    else
                        elapsed_seconds <= elapsed_seconds + 7'd1;
                end
                else begin
                    second_divider <= second_divider + 7'd1;
                end

                page_last <= page_sync1;

                if (feature_mask[1] && (page_sync1 != page_last)) begin
                    transition_active <= 1'b1;
                    transition_x <= 12'd0;
                end
                else if (transition_active) begin
                    if (transition_x >= SCREEN_W)
                        transition_active <= 1'b0;
                    else
                        transition_x <= transition_x + 12'd32;
                end
            end

            if (!i_vs && vs_d) begin
                x <= 12'd0;
                y <= 12'd0;
            end
            else if (i_de) begin
                if (!de_d)
                    x <= 12'd1;
                else
                    x <= x + 12'd1;

                if ((!de_d) && (y != 0))
                    y <= y;
            end
            else if (de_d) begin
                y <= y + 12'd1;
                x <= 12'd0;
            end

        end
    end

    always @(posedge clk) begin
        if (rst) begin
            p1_hs <= 1'b0; p1_vs <= 1'b0; p1_de <= 1'b0;
            p2_hs <= 1'b0; p2_vs <= 1'b0; p2_de <= 1'b0;
            p3_hs <= 1'b0; p3_vs <= 1'b0; p3_de <= 1'b0;
            p4_hs <= 1'b0; p4_vs <= 1'b0; p4_de <= 1'b0;
            p5_hs <= 1'b0; p5_vs <= 1'b0; p5_de <= 1'b0;
            p1_x <= 12'd0; p1_y <= 12'd0;
            p2_x <= 12'd0; p2_y <= 12'd0;
            p3_x <= 12'd0; p3_y <= 12'd0;
            p4_x <= 12'd0; p4_y <= 12'd0;
            p5_x <= 12'd0; p5_y <= 12'd0;
            p1_rgb <= 24'd0; p2_rgb <= 24'd0;
            p3_rgb <= 24'd0; p4_rgb <= 24'd0; p5_rgb <= 24'd0;
            p3_text_rgb <= 24'd0;
            p3_text_alpha <= 8'd0;
            p3_bars_rgb <= 24'd0;
            p3_bars_alpha <= 8'd0;
            p3_wave_rgb <= 24'd0;
            p3_wave_alpha <= 8'd0;
            p4_bars_rgb <= 24'd0;
            p4_bars_alpha <= 8'd0;
            p4_wave_rgb <= 24'd0;
            p4_wave_alpha <= 8'd0;
            p5_wave_rgb <= 24'd0;
            p5_wave_alpha <= 8'd0;
            o_hs <= 1'b0; o_vs <= 1'b0; o_de <= 1'b0;
            o_x <= 12'd0; o_y <= 12'd0; o_rgb <= 24'd0;
        end
        else begin
            p1_hs <= i_hs;
            p1_vs <= i_vs;
            p1_de <= i_de;
            p1_x  <= x;
            p1_y  <= y;
            p1_rgb <= processed_base;

            p2_hs <= p1_hs;
            p2_vs <= p1_vs;
            p2_de <= p1_de;
            p2_x  <= p1_x;
            p2_y  <= p1_y;
            p2_rgb <= transition_mixed;

            p3_hs <= p2_hs;
            p3_vs <= p2_vs;
            p3_de <= p2_de;
            p3_x  <= p2_x;
            p3_y  <= p2_y;
            p3_rgb <= p2_rgb;
            p3_text_rgb <= text_rgb;
            p3_text_alpha <= text_alpha;
            p3_bars_rgb <= bars_rgb;
            p3_bars_alpha <= active_bars_alpha;
            p3_wave_rgb <= waveform_rgb;
            p3_wave_alpha <= active_wave_alpha;

            p4_hs <= p3_hs;
            p4_vs <= p3_vs;
            p4_de <= p3_de;
            p4_x  <= p3_x;
            p4_y  <= p3_y;
            p4_rgb <= text_mixed;
            p4_bars_rgb <= p3_bars_rgb;
            p4_bars_alpha <= p3_bars_alpha;
            p4_wave_rgb <= p3_wave_rgb;
            p4_wave_alpha <= p3_wave_alpha;

            p5_hs <= p4_hs;
            p5_vs <= p4_vs;
            p5_de <= p4_de;
            p5_x  <= p4_x;
            p5_y  <= p4_y;
            p5_rgb <= bars_mixed;
            p5_wave_rgb <= p4_wave_rgb;
            p5_wave_alpha <= p4_wave_alpha;

            o_hs <= p5_hs;
            o_vs <= p5_vs;
            o_de <= p5_de;
            o_x  <= p5_x;
            o_y  <= p5_y;
            o_rgb <= wave_mixed;
        end
    end

endmodule

module audio_waveform_overlay #(
    parameter integer SCREEN_W = 1280,
    parameter integer SCREEN_H = 720,
    // 示波器区域（默认放在左侧中部，避开顶部标题和底部字幕）
    parameter integer WAVE_W = 256,
    parameter integer WAVE_H = 180,
    parameter integer WAVE_X = 40,
    parameter integer WAVE_Y = 150,
    // 每个采样点占用的横向像素数。**必须是 2 的幂**（取点索引用位移）。
    // 一屏画几个点由 WAVE_W / POINT_PX 推导（见下面的 N_POINTS），
    // 不再另设一个常数 —— 以前 WAVE_W 和采集深度 64 是两处独立的数，
    // 改一处、另一处不动，框宽和波形就会静默错位。
    parameter integer POINT_PX = 4,
    // 每 SAMPLE_STEP 个 I2S 样本取一个点：越大，一屏画出的周期越多
    parameter integer SAMPLE_STEP = 5
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        frame_tick,        // 帧边界脉冲，用来重新触发一次采集
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
    localparam integer TRACE_HALF  = 1;      // 线条半宽，1 表示 3 像素粗
    // 一屏几个采样点。WAVE_W=192 / POINT_PX=4 -> 48 个点，采集深度与
    // 框宽从此**同一个来源**，不会再各改各的。
    //
    // ⚠️ 改 WAVE_H 时的约束：绘制偏移是 |sample8|>>1，满幅 63 px
    //    （见下面 offset_d）。半高 (WAVE_H-1)/2 必须 >= 63 + 边框 3 px，
    //    即 **WAVE_H >= 135**。当前 140，半高 70，余量 4 px。
    //    改小了波形会顶到边框上被削平 —— 要缩小框就先动
    //    WAVE_W/POINT_PX（点数），别动高度。
    localparam integer N_POINTS    = WAVE_W / POINT_PX;
    // 由 POINT_PX / N_POINTS 推出来的两个宽度 —— 这样"改 WAVE_W"才是真的
    // 只改一个数。$clog2 在本工程里已经用过（scaling_pattern_writer.v /
    // smart_terminal_core.v），TD 支持。
    localparam integer PX_SHIFT    = $clog2(POINT_PX);   // 4 -> 2
    localparam integer IDX_W       = $clog2(N_POINTS);   // 48 -> 6

    // ------------------------------------------------------------------
    // 采集侧
    //
    // 旧版每来一个 48 kHz 样本就往 history 里写一个点，而一帧显示要
    // 16.7 ms，缓冲会被覆盖 12 次以上，扫描到哪一行读到的内容都不一样，
    // 屏幕上是跳动的噪点而不是波形。
    //
    // 现在改成"每帧采一次"：
    //   1. 帧边界把上一帧采好的缓冲整块交给显示侧（乒乓），
    //      所以一整帧扫描期间读到的数据是同一份，画面不会撕裂；
    //   2. 等到音频信号正过零再开始采，起点每帧都锁在同一个相位，
    //      波形在屏幕上不会左右跑；
    //   3. 每隔 SAMPLE_STEP 个样本取一点，N_POINTS 个点正好铺满面板宽度。
    // ------------------------------------------------------------------
    // 两页共用一个 128x8 的分布式 RAM：高 1 位选页，低 IDX_W 位选点。
    // 刻意不写复位初值——写了初值综合就会把它做成 1024 个带复位的触发器，
    // 而这块板 LUT 已经用到接近 8 成，多出的面积会直接反映到布线时序上。
    // 不写初值则推断为 LUTRAM；上电后前几帧显示空缓冲，第 2 帧起就有波形。
    reg [7:0]  cap_ram [0:127];
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
    // 等过零的上限，约 9.3 ms @75 MHz。
    //
    // 这里原来取 100000（1.33 ms），比最低音 C4 的周期 3.82 ms 还短：
    // 采集只要落在过零点之后，就必定等不到下一个上升沿，于是超时分支
    // 接管，采集起点每帧都不一样，屏幕上就是波形左右乱跳。音阶在
    // C4~C5 之间轮转，只有高音偶尔能正常触发，看起来就是"不太稳定"。
    // 现在留出两个 C4 周期以上的余量，正常音调一定由真正的过零点触发，
    // 只有真的静音时才会走到超时分支。
    localparam integer ZERO_TIMEOUT  = 700000;

    wire cap_zero_cross = cap_prev_sign && !audio_sample[23];
    wire cap_last_point = (cap_step == (SAMPLE_STEP - 1));
    // Preserve the existing x4 display gain, saturating instead of wrapping
    // a full-scale 24-bit input into the opposite sign. RAM remains unreset;
    // cap_display_valid hides its contents until a complete capture is shown.
    wire [7:0] capture_sample = !audio_sample[23] && (|audio_sample[22:21]) ? 8'h7f :
                                audio_sample[23] && (audio_sample[22:21] != 2'b11) ? 8'h80 :
                                audio_sample[21:14];

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

                            // 采满 N_POINTS 个点就交页（N_POINTS 由 WAVE_W 推导，
                            // 不再是写死的 63）
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

    // ------------------------------------------------------------------
    // 显示侧：读 RAM 与"算波形/比较/混色"拆成两级流水
    //
    // 如果全挤在一拍里，从分布式 RAM 读出到叠加层寄存器会有 15 级逻辑，
    // 75 MHz 下 setup 差 -0.425 ns。本模块在叠加层里的坐标因此接
    // s2_x/s2_y 而不是 s3_x/s3_y，多出来的这一级正好抵消。
    // ------------------------------------------------------------------
    reg [11:0] x_d;
    reg [11:0] y_d;
    reg [7:0]  sample_d;
    reg [11:0] x_d2;
    reg [11:0] y_d2;
    reg [7:0]  offset_d;
    reg        sign_d;

    // 第几个采样点 = (x - 左沿) / POINT_PX，用 PX_SHIFT 而不是写死 >>2
    wire [IDX_W-1:0] sample_index = (x - WAVE_LEFT) >> PX_SHIFT;
    wire [IDX_W:0]   cap_rd_addr  = {cap_rd_page, sample_index};

    // 显示侧两级流水：|sample| 的取反加一和缩放单独占一级。
    // 这两步和后面的"算 wave_y + 比较 + 混色"挤在一拍里时，
    // 从 sample_d 到 s4_wave_rgb 实测 14.2 ns（14 级逻辑、9 个加法器），
    // 超过 13.3 ns 周期。拆开之后两级各只剩几级逻辑。
    always @(posedge clk) begin
        if (rst) begin
            x_d      <= 12'd0;
            y_d      <= 12'd0;
            sample_d <= 8'd0;
            x_d2     <= 12'd0;
            y_d2     <= 12'd0;
            offset_d <= 8'd0;
            sign_d   <= 1'b0;
        end
        else begin
            x_d      <= x;
            y_d      <= y;
            sample_d <= cap_display_valid ? cap_ram[cap_rd_addr] : 8'd0;

            // 第一级：|sample|/2，满幅 128 -> 64，面板半高 90，余量充足
            sign_d   <= sample_d[7];
            offset_d <= sample_d[7] ? ((~sample_d + 8'd1) >> 1)
                                    : (sample_d >> 1);
            x_d2     <= x_d;
            y_d2     <= y_d;
        end
    end

    // ---- 由两级流水后的值生成像素 ----
    wire in_region = (x_d2 >= WAVE_LEFT) && (x_d2 <= WAVE_RIGHT) &&
                     (y_d2 >= WAVE_TOP)  && (y_d2 <= WAVE_BOTTOM);

    wire [11:0] wave_y = sign_d ?
                         (WAVE_CENTER - {4'b0, offset_d}) :
                         (WAVE_CENTER + {4'b0, offset_d});

    // ------------------------------------------------------------------
    // 2026-09-18 第二次上板反馈："框里的波点跳动，希望更准确清晰"。
    //
    // 原因是**点与点之间没有连线**：每个采样点占 POINT_PX=4 个像素列，
    // 画成一个 4×3 的方块（TRACE_HALF=1 是上下各 1 px）。相邻两点的
    // 垂直落差按实测约 6 px（SAMPLE_STEP=5 个样本，C4 三角波每样本走
    // 约 2.8 个单位 → 5 个样本 ≈ 13 个 8bit 单位 → offset 差 6 px），
    // 比方块本身还高，于是看上去是一串**断开的点在跳**，不是一条波。
    //
    // 修法：把上一列的 y 记一拍，本列除了画自己那 3 px，再把
    // [上一列的 y, 本列的 y] 这一段竖向补上 —— 相当于"连点成线"的
    // 阶梯版。只多一个寄存器 + 两个比较器。
    //
    // ⚠️ wave_y_r 是**上一列**的值（同一拍里 wave_y 已经变成本列的值），
    //    所以段内 4 列中只有"换点的那一列"落差非零，正好把缝隙补在
    //    正确的列上。x_d2 == WAVE_LEFT 那一列的上一列在区域外，
    //    wave_y_r 是上一行的残留值，必须排除，否则左边界会多一条假竖线。
    // ------------------------------------------------------------------
    reg [11:0] wave_y_r;

    always @(posedge clk) begin
        if (rst) wave_y_r <= WAVE_CENTER[11:0];
        else     wave_y_r <= wave_y;
    end

    wire [11:0] y_lo    = (wave_y_r < wave_y) ? wave_y_r : wave_y;
    wire [11:0] y_hi    = (wave_y_r < wave_y) ? wave_y : wave_y_r;
    wire        conn_on = in_region && (x_d2 > WAVE_LEFT) &&
                          (y_d2 >= y_lo) && (y_d2 <= y_hi);

    wire axis_on = in_region && ((y_d2 == WAVE_CENTER) ||
                                 (y_d2 == (WAVE_CENTER + 12'd1)));
    wire trace_on = in_region &&
                    (y_d2 >= (wave_y - TRACE_HALF)) &&
                    (y_d2 <= (wave_y + TRACE_HALF));
    // 线条像素 = 本点那 3 px 或 连线段
    wire trace_px = trace_on || conn_on;
    wire frame_on = in_region &&
                    (((x_d2 - WAVE_LEFT) < 3) ||
                     ((x_d2 - WAVE_LEFT) >= (WAVE_W - 3)) ||
                     ((y_d2 - WAVE_TOP) < 3) ||
                     ((y_d2 - WAVE_TOP) >= (WAVE_H - 3)));

    always @(*) begin
        if (trace_px) begin
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
        else if (in_region) begin
            // 面板底色：让示波器区域在整幅画面上明显可辨
            wave_rgb   = 24'h061420;
            wave_alpha = 8'd150;
        end
        else begin
            wave_rgb   = 24'h000000;
            wave_alpha = 8'd0;
        end
    end

endmodule
