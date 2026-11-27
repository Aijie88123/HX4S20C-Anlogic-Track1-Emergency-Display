`timescale 1ns/1ps

module i2s_receiver_24 (
    input  wire        clk,
    input  wire        rst,
    input  wire        i2s_bclk,
    input  wire        i2s_lrck,
    input  wire        i2s_dout,

    output reg         audio_valid,
    output reg [23:0]  audio_left,
    output reg [23:0]  audio_right
);

    reg [1:0] bclk_sync;
    reg [1:0] lrck_sync;
    reg [1:0] dout_sync;

    reg [63:0] left_shift;
    reg [63:0] right_shift;
    reg [63:0] left_lock;

    wire bclk_rise = !bclk_sync[1] && bclk_sync[0];
    wire lrck_rise = !lrck_sync[1] && lrck_sync[0];
    wire lrck_fall = lrck_sync[1] && !lrck_sync[0];

    always @(posedge clk) begin
        bclk_sync <= {bclk_sync[0], i2s_bclk};
        lrck_sync <= {lrck_sync[0], i2s_lrck};
        dout_sync <= {dout_sync[0], i2s_dout};
    end

    always @(posedge clk) begin
        if (rst) begin
            left_shift  <= 64'd0;
            right_shift <= 64'd0;
            left_lock   <= 64'd0;
        end
        else if (bclk_rise) begin
            if (lrck_sync[1]) begin
                right_shift <= {right_shift[62:0], dout_sync[1]};
            end
            else begin
                left_shift  <= {left_shift[62:0], dout_sync[1]};
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            audio_valid <= 1'b0;
            audio_left  <= 24'd0;
            audio_right <= 24'd0;
            left_lock   <= 64'd0;
        end
        else begin
            audio_valid <= 1'b0;

            if (lrck_rise) begin
                left_lock <= left_shift;
            end

            if (lrck_fall) begin
                audio_valid <= 1'b1;
                audio_left  <= left_lock[63:40];
                audio_right <= right_shift[63:40];
            end
        end
    end

endmodule
