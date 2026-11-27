`timescale 1ns/1ps

module scaling_pattern_writer #(
    parameter integer H_ACTIVE = 640,
    parameter integer V_ACTIVE = 480,
    parameter integer SRC_W    = 320,
    parameter integer SRC_H    = 240
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        Sdr_init_done,

    output reg         write_req,
    input  wire        write_req_ack,
    output wire        write_en,
    output wire [31:0] write_data,
    output reg         frame_done
);

    localparam integer PIXELS = H_ACTIVE * V_ACTIVE;
    localparam integer ADDR_W = $clog2(PIXELS);

    localparam [1:0] IDLE    = 2'd0;
    localparam [1:0] REQUEST = 2'd1;
    localparam [1:0] STREAM  = 2'd2;
    localparam [1:0] DONE    = 2'd3;

    reg [1:0] state;
    reg       active;
    reg [ADDR_W-1:0] pixel_count;
    reg [9:0] x;
    reg [9:0] y;

    wire [9:0] src_x = x >> 1;
    wire [9:0] src_y = y >> 1;

    function [23:0] scaled_color;
        input [9:0] sx;
        input [9:0] sy;
        begin
            if (sy >= (SRC_H / 2)) begin
                if (sx[5] ^ sy[5])
                    scaled_color = 24'h404040;
                else
                    scaled_color = 24'hC0C0C0;
            end
            else if (sx < (SRC_W / 5))
                scaled_color = 24'hFF0000;
            else if (sx < ((SRC_W * 2) / 5))
                scaled_color = 24'h00FF00;
            else if (sx < ((SRC_W * 3) / 5))
                scaled_color = 24'h0000FF;
            else if (sx < ((SRC_W * 4) / 5))
                scaled_color = 24'hFFFFFF;
            else
                scaled_color = 24'h000000;
        end
    endfunction

    assign write_en   = active;
    assign write_data = {scaled_color(src_x, src_y), 8'b0};

    always @(posedge clk) begin
        if (rst) begin
            state       <= IDLE;
            active      <= 1'b0;
            write_req   <= 1'b0;
            pixel_count <= {ADDR_W{1'b0}};
            x           <= 10'd0;
            y           <= 10'd0;
            frame_done  <= 1'b0;
        end
        else begin
            case (state)
                IDLE: begin
                    frame_done <= 1'b0;
                    if (start && Sdr_init_done) begin
                        write_req <= 1'b1;
                        state     <= REQUEST;
                    end
                end

                REQUEST: begin
                    if (write_req_ack) begin
                        write_req   <= 1'b0;
                        active      <= 1'b1;
                        pixel_count <= {ADDR_W{1'b0}};
                        x           <= 10'd0;
                        y           <= 10'd0;
                        state       <= STREAM;
                    end
                end

                STREAM: begin
                    if (x == H_ACTIVE - 1) begin
                        x <= 10'd0;
                        if (y == V_ACTIVE - 1) begin
                            active     <= 1'b0;
                            frame_done <= 1'b1;
                            state      <= DONE;
                        end
                        else begin
                            y <= y + 10'd1;
                        end
                    end
                    else begin
                        x <= x + 10'd1;
                    end

                    if (pixel_count == PIXELS - 1)
                        pixel_count <= {ADDR_W{1'b0}};
                    else
                        pixel_count <= pixel_count + 1'b1;
                end

                DONE: begin
                    active     <= 1'b0;
                    write_req  <= 1'b0;
                    frame_done <= 1'b1;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
