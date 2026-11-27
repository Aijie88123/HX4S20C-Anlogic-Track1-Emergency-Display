`timescale 1ns/1ps

// 音频能量检波：峰值保持 + 缓慢回落
//
// 上一版直接取 |sample| 的瞬时值，对三角波来说每个采样点都在
// 0..峰值之间来回变，能量条会以信号频率抖动成一团噪点。
// 这里改成"取到更大的值就立刻抬上去，否则按固定速率慢慢下降"，
// 这样能量条跟随的是幅度包络，而不是瞬时波形。
module audio_envelope #(
    // 每 DECAY_DIV+1 个时钟把保持值减 1；仅新峰值重置计时。
    // 75 MHz 下 960 拍约 12.8 us，满幅 0x1E84 完全泄放约 100 ms，
    // 快于音频包络（正常 1.2 Hz 的半周期约 400 ms），跟得上又不闪烁。
    parameter integer DECAY_DIV = 960
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        sample_valid,
    input  wire [23:0] sample_left,

    output reg  [15:0] magnitude
);

    reg [23:0] abs_sample;

    always @(*) begin
        if (sample_left[23])
            abs_sample = (~sample_left) + 24'd1;
        else
            abs_sample = sample_left;
    end

    wire [15:0] sample_mag = abs_sample[23:8];

    reg [15:0] decay_cnt;

    always @(posedge clk) begin
        if (rst) begin
            magnitude <= 16'd0;
            decay_cnt <= 16'd0;
        end
        else if (sample_valid && (sample_mag > magnitude)) begin
            decay_cnt <= 16'd0;
            magnitude <= sample_mag;
        end
        else if (decay_cnt >= DECAY_DIV[15:0]) begin
            decay_cnt <= 16'd0;
            if (magnitude != 16'd0)
                magnitude <= magnitude - 16'd1;
        end
        else begin
            decay_cnt <= decay_cnt + 16'd1;
        end
    end

endmodule
