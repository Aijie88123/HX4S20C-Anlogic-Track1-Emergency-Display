
module hdmi_audio_tone_i2s_64fs #(
    // Default off preserves all legacy named-port users and test tones.
    parameter integer PAGE_LINK_ENABLE = 0,
    parameter integer EXACT_48K_ENABLE = 0,
    parameter [31:0] PHASE_INC = 32'd39370534,   // 兼容旧顶层，实际本版内部不用它
    parameter signed [23:0] AMP = 24'sd2000000,
    parameter integer NOTE_HOLD_FRAMES = 24000,  // 每个音持续 0.5s @ 48kHz
    parameter integer EMERGENCY_HOLD_FRAMES = 12000, // 0.25s @ 48kHz
    // 幅度包络相位增量（48kHz 采样）：一个完整包络周期 = 2^32 / INC
    //   正常 1.2Hz -> 107374, 应急 4Hz -> 357913
    // 加包络的原因：固定幅度的方波在示波器面板上是一条不动的直线，
    // 右下能量条也永远顶在同一个高度，"看不出变化"。
    parameter [31:0] ENV_INC_NORMAL    = 32'd107374,
    parameter [31:0] ENV_INC_EMERGENCY = 32'd357913
)(
    input  wire I_mclk,      // Current board: ~12.295082MHz; LRCK = MCLK/256
    input  wire I_rst,
    input  wire I_emergency,
    output reg  O_i2s_BCLK,
    output reg  O_i2s_LRCK,
    output reg  O_i2s_DOUT,
    input wire [2:0] I_page_index,
    input wire I_page_update,
    input wire I_page_emergency,
    output wire O_sample_tick
);

// do/re/mi/fa/so/la/si/do  （C4 D4 E4 F4 G4 A4 B4 C5）
// 相位增量按 48kHz 采样率计算
function [31:0] note_inc_lut;
    input [2:0] idx;
    begin
        case (idx)
            3'd0: note_inc_lut = 32'd23409862; // do  C4 261.63Hz
            3'd1: note_inc_lut = 32'd26276681; // re  D4 293.66Hz
            3'd2: note_inc_lut = 32'd29494578; // mi  E4 329.63Hz
            3'd3: note_inc_lut = 32'd31248410; // fa  F4 349.23Hz
            3'd4: note_inc_lut = 32'd35075155; // so  G4 392.00Hz
            3'd5: note_inc_lut = 32'd39370534; // la  A4 440.00Hz
            3'd6: note_inc_lut = 32'd44191930; // si  B4 493.88Hz
            default: note_inc_lut = 32'd46819716; // do  C5 523.25Hz
        endcase
    end
endfunction

reg  [5:0]  S_bit_cnt;
reg  [63:0] S_shift_reg;
reg  [31:0] S_phase_acc;
reg  [31:0] S_env_acc;
reg signed [23:0] S_sample_word;
reg  [2:0]  S_note_idx;
reg [15:0]  S_note_frame_cnt;
reg [15:0]  S_emergency_frame_cnt;
reg         S_emergency_tone_hi;
reg [1:0] S_emergency_sync;
reg S_page_is_alarm;
reg S_emergency_applied;

// Normal image commits never restart the original C4..C5 melody.
// Committed mode metadata still holds the alarm until a normal frame returns.

// PLL C2 = 750MHz / 61. Its 256-cycle sample rate is 48027.663934Hz.
// Clock-enable ratio 15616/15625 converts that to exactly 48000Hz on average.
// All registers retain the original PLL clock: no gated clock or extra PLL.
// Only 9 of every 15625 cycles are held, distributing the fractional correction.
reg [13:0] audio_rate_phase;
wire audio_clock_enable = !EXACT_48K_ENABLE || audio_rate_phase >= 14'd9;
always @(posedge I_mclk or posedge I_rst)begin
 if(I_rst) audio_rate_phase<=14'd15624;
 else if(audio_rate_phase>=14'd9) audio_rate_phase<=audio_rate_phase-14'd9;
 // Underflow implies phase=0..8; 15616=0x3D00, so no second adder.
 else audio_rate_phase<={6'd61,4'd0,audio_rate_phase[3:0]};
end
assign O_sample_tick = audio_clock_enable && O_i2s_BCLK && (S_bit_cnt == 6'd63) && O_i2s_LRCK;
wire W_page_alarm = I_page_update ? I_page_emergency : S_page_is_alarm;
// Alarm wins immediately after two synchronization clocks, and remains active
// after S4 clears until an ordinary frame is actually committed/restored.
wire W_emergency_active = PAGE_LINK_ENABLE ?
    (S_emergency_sync[1] || W_page_alarm) : I_emergency;

wire [31:0] W_emergency_inc = S_emergency_tone_hi ?
                              32'd107374182 : 32'd71582788;
wire [31:0] W_note_inc = W_emergency_active ?
                         W_emergency_inc : note_inc_lut(S_note_idx);

// ---------------------------------------------------------------------
// 波形发生：方波 -> 三角波
//   方波每一帧的采样值都是同一个 ±AMP，波形显示出来是两根横线，
//   三角波每个采样点连续变化，64 点窗口才画得出形状。
//   三角波谐波按 1/n^2 衰减，听感也比方波柔和。
// ---------------------------------------------------------------------
wire [7:0] W_tri_phase = S_phase_acc[31:24];
wire [8:0] W_tri_dbl   = {W_tri_phase, 1'b0};                  // 0..510
wire signed [9:0] W_tri_rise = {1'b0, W_tri_dbl} - 10'sd128;   // -128 .. +126
wire signed [9:0] W_tri_fall = 10'sd383 - {1'b0, W_tri_dbl};   // +127 .. -127
wire signed [9:0] W_tri_val  = W_tri_phase[7] ? W_tri_fall : W_tri_rise;

// ---------------------------------------------------------------------
// 幅度包络：三角波包络 0..127，最轻约 50%、最响约 100%
//   amplitude = AMP/2 + AMP * env / 256
// ---------------------------------------------------------------------
wire [31:0] W_env_inc   = W_emergency_active ? ENV_INC_EMERGENCY : ENV_INC_NORMAL;
wire [7:0]  W_env_phase = S_env_acc[31:24];
wire [6:0]  W_env_tri   = W_env_phase[7] ?
                          (~W_env_phase[6:0]) : W_env_phase[6:0];
wire [30:0] W_env_prod  = AMP[23:0] * W_env_tri;               // < 2^28
wire [23:0] W_env_amp   = {1'b0, AMP[23:1]} + W_env_prod[30:8];

wire signed [7:0]  W_tri_val8  = W_tri_val[7:0];
wire signed [39:0] W_tri_prod  = W_tri_val8 * $signed({1'b0, W_env_amp});
wire signed [23:0] W_sample    = W_tri_prod[30:7];

always @(posedge I_mclk or posedge I_rst) begin
    if (I_rst) begin
        O_i2s_BCLK      <= 1'b0;
        O_i2s_LRCK      <= 1'b0;
        O_i2s_DOUT      <= 1'b0;
        S_bit_cnt       <= 6'd0;
        S_shift_reg     <= 64'd0;
        S_phase_acc     <= 32'd0;
        S_env_acc       <= 32'd0;
        S_sample_word   <= 24'sd0;
        S_note_idx      <= 3'd0;
        S_note_frame_cnt<= 16'd0;
        S_emergency_frame_cnt <= 16'd0;
        S_emergency_tone_hi   <= 1'b0;
        S_emergency_sync <= 2'b00;
        S_page_is_alarm <= 1'b0;
        S_emergency_applied <= 1'b0;
    end
    else begin
        S_emergency_sync <= {S_emergency_sync[0], I_emergency};
        if(audio_clock_enable)begin
        // 保持和你现有接收端兼容的 64fs 发送时序
        O_i2s_BCLK <= ~O_i2s_BCLK;

        if (O_i2s_BCLK == 1'b1) begin
            O_i2s_DOUT  <= S_shift_reg[63];
            S_shift_reg <= {S_shift_reg[62:0], 1'b0};

            if (S_bit_cnt == 6'd63) begin
                S_bit_cnt <= 6'd0;

                if (O_i2s_LRCK == 1'b0) begin
                    // 左声道发完，右声道复用同一个样本
                    O_i2s_LRCK  <= 1'b1;
                    S_shift_reg <= {S_sample_word[23:0], 40'd0};
                end
                else begin
                    // 右声道发完，进入下一帧样本
                    O_i2s_LRCK  <= 1'b0;

                    S_phase_acc <= S_phase_acc + W_note_inc;
                    S_env_acc   <= S_env_acc + W_env_inc;

                    // Latch the exact word serialized to the left channel.
                    // The right half-frame must reuse this same sample, not
                    // the prior sample from an extra pipeline register.
                    S_sample_word <= W_sample;
                    S_shift_reg   <= {W_sample, 40'd0};

                    if (PAGE_LINK_ENABLE) begin
                        S_emergency_applied <= W_emergency_active;
                        if (I_page_update) begin
                            S_page_is_alarm <= I_page_emergency;
                        end
                    end
                    if (W_emergency_active) begin
                        S_note_frame_cnt      <= 16'd0;
                        S_note_idx            <= 3'd0;

                        if (S_emergency_frame_cnt ==
                            EMERGENCY_HOLD_FRAMES - 1) begin
                            S_emergency_frame_cnt <= 16'd0;
                            S_emergency_tone_hi <= ~S_emergency_tone_hi;
                        end
                        else begin
                            S_emergency_frame_cnt <=
                                S_emergency_frame_cnt + 16'd1;
                        end
                    end
                    else begin
                        S_emergency_frame_cnt <= 16'd0;
                        S_emergency_tone_hi   <= 1'b0;

                        // Normal picture commits do not touch this timer or
                        // note position: finish every note and all eight notes.
                        if (S_note_frame_cnt == NOTE_HOLD_FRAMES - 1) begin
                            S_note_frame_cnt <= 16'd0;
                            if (S_note_idx == 3'd7)
                                S_note_idx <= 3'd0;
                            else
                                S_note_idx <= S_note_idx + 3'd1;
                        end
                        else begin
                            S_note_frame_cnt <= S_note_frame_cnt + 16'd1;
                        end
                    end
                end
            end
            else begin
                S_bit_cnt <= S_bit_cnt + 6'd1;
            end
        end
        end // audio_clock_enable
    end
end

endmodule
