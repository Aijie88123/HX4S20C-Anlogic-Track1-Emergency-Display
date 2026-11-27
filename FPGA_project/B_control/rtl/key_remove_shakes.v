/*
creat time: 2020/12/3 15:50

engineer:   xiong guo qiang

description:
对按键操作进行消抖操作，每次按下产生一个时钟周期的高脉冲

---- 2026-09-13 修改说明 ----
原实现的问题：
    原版用 S_delay_cnt == 'd100000 作为触发条件，即按键必须被按住
    100000 个时钟周期才会输出一次脉冲。在 75 MHz 的 video_clk 下这是
    1.33 ms；更糟的是这段时间内 S_delay_en 一直保持有效，若按键先被
    按下又松开（或按下时抖动），计数器走完后 S_key_in_sync_4d 已经
    回到高电平，脉冲被整个丢弃，同时这段时间里的第二次按键也会被吞掉。
    上板表现为"按 S4 没反应"。

现实现：
    标准的 N 拍稳定去抖 + 按下沿（低电平有效）检测，按下即输出一个
    时钟周期脉冲，不再要求最小按住时长，也不再吞掉后续按键。
    行为与原设计一致：每次按下只产生一个脉冲。
*/

module key_remove_shakes #(
	parameter integer CLK_FREQ_HZ = 75_000_000,
	// 触点抖动通常 < 5 ms；5 ms 既能吸收抖动，又不会吞掉人手轻点。
	parameter integer DEBOUNCE_MS = 5
)(
	input wire      I_clk,
	input wire      I_rst_n,

	input wire      I_key_in,

	output reg      O_key_trig_out
);

	localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

	/// 同步到处理时钟域，打两拍
	reg  S_key_in_sync_1d;
	reg  S_key_in_sync_2d;

	/// 去抖后的稳定电平（1 = 松开，0 = 按下）
	reg  S_key_stable;
	reg  S_key_stable_1d;

	reg[31:0] S_debounce_cnt;

	/// 稳定电平的下降沿 = 一次有效按下
	wire S_key_press_edge = S_key_stable_1d & ~S_key_stable;

	always @ (posedge I_clk or negedge I_rst_n) begin
		if(!I_rst_n) begin
			S_key_in_sync_1d <= 1'b1;
			S_key_in_sync_2d <= 1'b1;
			S_key_stable     <= 1'b1;
			S_key_stable_1d  <= 1'b1;
			S_debounce_cnt   <= 32'd0;
		end
		else begin
			S_key_in_sync_1d <= I_key_in;
			S_key_in_sync_2d <= S_key_in_sync_1d;

			// 输入与当前稳定值一致时计数清零；否则累积到 DEBOUNCE_CYCLES 才认账
			if(S_key_in_sync_2d == S_key_stable) begin
				S_debounce_cnt <= 32'd0;
			end
			else if(S_debounce_cnt >= DEBOUNCE_CYCLES - 1) begin
				S_debounce_cnt <= 32'd0;
				S_key_stable   <= S_key_in_sync_2d;
			end
			else begin
				S_debounce_cnt <= S_debounce_cnt + 32'd1;
			end

			S_key_stable_1d <= S_key_stable;
		end
	end

	always @ (posedge I_clk or negedge I_rst_n) begin
		if(!I_rst_n)
			O_key_trig_out <= 1'b0;
		else
			O_key_trig_out <= S_key_press_edge;
	end

endmodule
