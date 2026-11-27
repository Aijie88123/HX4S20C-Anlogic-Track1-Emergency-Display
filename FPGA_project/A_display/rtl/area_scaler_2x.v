`timescale 1ns/1ps

module area_scaler_2x #(
    parameter integer IN_WIDTH  = 320,
    parameter integer OUT_WIDTH = 640
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        in_valid,
    input  wire [23:0] in_rgb,
    input  wire        in_line_last,
    output wire        in_ready,

    output reg         out_valid,
    output reg  [23:0] out_rgb,
    output reg         out_line_last
);

    localparam CAPTURE = 2'd0;
    localparam PASS_1  = 2'd1;
    localparam PASS_2  = 2'd2;

    reg [1:0]  state;
    reg [9:0]  wr_addr;
    reg [9:0]  rd_addr;
    reg [23:0] line_buf [0:OUT_WIDTH-1];

    assign in_ready = (state == CAPTURE);

    always @(posedge clk) begin
        if (rst) begin
            state         <= CAPTURE;
            wr_addr       <= 10'd0;
            rd_addr       <= 10'd0;
            out_valid     <= 1'b0;
            out_rgb       <= 24'd0;
            out_line_last <= 1'b0;
        end
        else begin
            out_valid     <= 1'b0;
            out_line_last <= 1'b0;

            case (state)
                CAPTURE: begin
                    if (in_valid && in_ready) begin
                        line_buf[wr_addr]       <= in_rgb;
                        line_buf[wr_addr + 10'd1] <= in_rgb;

                        if (wr_addr >= OUT_WIDTH - 2) begin
                            wr_addr <= 10'd0;
                            rd_addr <= 10'd0;
                            state   <= PASS_1;
                        end
                        else begin
                            wr_addr <= wr_addr + 10'd2;
                        end
                    end
                end

                PASS_1: begin
                    out_valid <= 1'b1;
                    out_rgb   <= line_buf[rd_addr];

                    if (rd_addr == OUT_WIDTH - 1) begin
                        rd_addr       <= 10'd0;
                        out_line_last <= 1'b1;
                        state         <= PASS_2;
                    end
                    else begin
                        rd_addr <= rd_addr + 10'd1;
                    end
                end

                PASS_2: begin
                    out_valid <= 1'b1;
                    out_rgb   <= line_buf[rd_addr];

                    if (rd_addr == OUT_WIDTH - 1) begin
                        rd_addr       <= 10'd0;
                        out_line_last <= 1'b1;
                        state         <= CAPTURE;
                    end
                    else begin
                        rd_addr <= rd_addr + 10'd1;
                    end
                end

                default: begin
                    state     <= CAPTURE;
                    out_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule
