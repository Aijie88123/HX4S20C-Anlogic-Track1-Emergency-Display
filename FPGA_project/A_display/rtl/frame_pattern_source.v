`timescale 1ns/1ps

module frame_pattern_source #(
    parameter integer WIDTH  = 320,
    parameter integer HEIGHT = 240
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        out_ready,

    output reg         out_valid,
    output reg  [23:0] out_rgb,
    output reg         out_line_last,
    output reg  [15:0] out_x,
    output reg  [15:0] out_y,
    output reg  [15:0] frame_id
);

    localparam SEND_LINE = 1'b0;
    localparam WAIT_LINE = 1'b1;

    reg state;

    function [23:0] pattern_pixel;
        input [15:0] px;
        input [15:0] py;
        input [15:0] fid;
        reg [23:0] color;
        reg [7:0]  ramp;
        begin
            ramp = {px[7:0] ^ {4'b0, fid[3:0]}};

            if ((px < 8) || (px >= WIDTH - 8) ||
                (py < 8) || (py >= HEIGHT - 8))
                color = 24'hF2A900;
            else if (py < 32)
                color = {8'h16, 8'h55, 8'h8A};
            else if (py < 64)
                color = {8'h0E, 8'h7C, 8'h66};
            else if (((px >> 5) ^ (py >> 5)) & 1'b1)
                color = {ramp, 8'h50, 8'h28};
            else
                color = {8'h28, ramp, 8'h88};

            pattern_pixel = color;
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state         <= WAIT_LINE;
            out_valid     <= 1'b0;
            out_rgb       <= 24'd0;
            out_line_last <= 1'b0;
            out_x         <= 16'd0;
            out_y         <= 16'd0;
            frame_id      <= 16'd0;
        end
        else begin
            out_line_last <= 1'b0;

            case (state)
                WAIT_LINE: begin
                    out_valid <= 1'b0;
                    if (out_ready) begin
                        out_valid <= 1'b1;
                        out_rgb   <= pattern_pixel(out_x, out_y, frame_id);
                        state     <= SEND_LINE;
                    end
                end

                SEND_LINE: begin
                    if (out_ready) begin
                        if (out_x == WIDTH - 1) begin
                            out_line_last <= 1'b1;
                            out_x         <= 16'd0;
                            out_valid     <= 1'b0;
                            state         <= WAIT_LINE;

                            if (out_y == HEIGHT - 1) begin
                                out_y    <= 16'd0;
                                frame_id <= frame_id + 16'd1;
                            end
                            else begin
                                out_y <= out_y + 16'd1;
                            end
                        end
                        else begin
                            out_x   <= out_x + 16'd1;
                            out_rgb <= pattern_pixel(out_x + 16'd1, out_y, frame_id);
                        end
                    end
                end

                default: begin
                    state     <= WAIT_LINE;
                    out_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule
