`timescale 1ns/1ps

module tone_i2s_64fs #(
    parameter integer MCLK_HZ        = 25_200_000,
    parameter integer SAMPLE_RATE_HZ = 48_000,
    parameter integer TONE_HZ        = 1_000,
    parameter signed [23:0] AMP      = 24'sd2_000_000
) (
    input  wire                  clk,
    input  wire                  rst,
    output reg                   bclk,
    output reg                   lrck,
    output reg                   dout,
    output reg signed [23:0]     sample_debug
);

    localparam integer BCLK_DIV = (MCLK_HZ / (SAMPLE_RATE_HZ * 128)) < 1 ?
                                  1 : (MCLK_HZ / (SAMPLE_RATE_HZ * 128));
    localparam integer HALF_PERIOD = (SAMPLE_RATE_HZ / TONE_HZ) / 2;

    reg [7:0]  div_cnt;
    reg [6:0]  bit_cnt;
    reg [63:0] left_word;
    reg [63:0] right_word;
    reg [15:0] tone_cnt;
    reg        sample_value;

    function [63:0] make_word;
        input sign;
        begin
            make_word = sign ? {-AMP, 40'd0} : {AMP, 40'd0};
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            div_cnt      <= 8'd0;
            bit_cnt      <= 7'd0;
            bclk         <= 1'b0;
            lrck         <= 1'b0;
            dout         <= 1'b0;
            left_word    <= make_word(1'b0);
            right_word   <= make_word(1'b0);
            tone_cnt     <= 16'd0;
            sample_value <= 1'b0;
            sample_debug <= AMP;
        end
        else if (div_cnt == BCLK_DIV - 1) begin
            div_cnt <= 8'd0;
            bclk    <= ~bclk;

            if (bclk) begin
                if (lrck == 1'b0) begin
                    dout      <= left_word[63];
                    left_word <= {left_word[62:0], 1'b0};
                end
                else begin
                    dout       <= right_word[63];
                    right_word <= {right_word[62:0], 1'b0};
                end

                if (bit_cnt == 7'd63) begin
                    bit_cnt <= 7'd0;

                    if (lrck == 1'b0) begin
                        lrck       <= 1'b1;
                        dout       <= right_word[63];
                        right_word <= {right_word[62:0], 1'b0};
                    end
                    else begin
                        lrck <= 1'b0;

                        if (tone_cnt == HALF_PERIOD - 1) begin
                            tone_cnt     <= 16'd0;
                            sample_value <= ~sample_value;
                        end
                        else begin
                            tone_cnt <= tone_cnt + 16'd1;
                        end

                        sample_debug <= sample_value ? -AMP : AMP;
                        left_word    <= make_word(sample_value);
                        right_word   <= make_word(sample_value);
                        dout         <= sample_value ? -AMP[23] : AMP[23];
                    end
                end
                else begin
                    bit_cnt <= bit_cnt + 7'd1;
                end
            end
        end
        else begin
            div_cnt <= div_cnt + 8'd1;
        end
    end

endmodule
