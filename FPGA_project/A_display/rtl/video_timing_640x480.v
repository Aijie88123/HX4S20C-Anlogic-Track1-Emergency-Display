`timescale 1ns/1ps

module video_timing_640x480 #(
    parameter integer H_ACTIVE = 640,
    parameter integer H_FRONT  = 16,
    parameter integer H_SYNC   = 96,
    parameter integer H_BACK   = 48,
    parameter integer V_ACTIVE = 480,
    parameter integer V_FRONT  = 10,
    parameter integer V_SYNC   = 2,
    parameter integer V_BACK   = 33
) (
    input  wire        clk,
    input  wire        rst,

    output reg         hs,
    output reg         vs,
    output reg         de,
    output reg  [11:0] x,
    output reg  [11:0] y,
    output reg         frame_start,
    output reg         frame_last
);

    localparam integer H_TOTAL = H_SYNC + H_BACK + H_ACTIVE + H_FRONT;
    localparam integer V_TOTAL = V_SYNC + V_BACK + V_ACTIVE + V_FRONT;
    localparam integer H_ACTIVE_BEGIN = H_SYNC + H_BACK;
    localparam integer H_ACTIVE_END   = H_ACTIVE_BEGIN + H_ACTIVE;
    localparam integer V_ACTIVE_BEGIN = V_SYNC + V_BACK;
    localparam integer V_ACTIVE_END   = V_ACTIVE_BEGIN + V_ACTIVE;

    always @(posedge clk) begin
        if (rst) begin
            x           <= 12'd0;
            y           <= 12'd0;
            hs          <= 1'b1;
            vs          <= 1'b1;
            de          <= 1'b0;
            frame_start <= 1'b0;
            frame_last  <= 1'b0;
        end
        else begin
            hs <= (x < H_SYNC);
            vs <= (y < V_SYNC);

            de <= (x >= H_ACTIVE_BEGIN) && (x < H_ACTIVE_END) &&
                  (y >= V_ACTIVE_BEGIN) && (y < V_ACTIVE_END);

            frame_start <= (x == H_ACTIVE_BEGIN) &&
                           (y == V_ACTIVE_BEGIN);
            frame_last  <= (x == (H_ACTIVE_END - 1)) &&
                           (y == (V_ACTIVE_END - 1));

            if (x == H_TOTAL - 1) begin
                x <= 12'd0;
                if (y == V_TOTAL - 1)
                    y <= 12'd0;
                else
                    y <= y + 12'd1;
            end
            else begin
                x <= x + 12'd1;
            end
        end
    end

endmodule
