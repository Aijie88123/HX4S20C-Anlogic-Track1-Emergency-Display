`timescale 1ns/1ps

module frame_buffer_pingpong #(
    parameter integer PIXELS = 640 * 480,
    parameter integer ADDR_W = 19
) (
    input  wire                  wr_clk,
    input  wire                  rst,
    input  wire                  wr_en,
    input  wire [ADDR_W-1:0]     wr_addr,
    input  wire [23:0]           wr_data,
    input  wire                  wr_commit,

    input  wire                  rd_clk,
    input  wire                  rd_en,
    input  wire [ADDR_W-1:0]     rd_addr,
    output wire [23:0]           rd_data,
    output reg                   frame_ready,
    output wire                  write_bank
);

    reg [23:0] mem0 [0:PIXELS-1];
    reg [23:0] mem1 [0:PIXELS-1];

    reg write_bank_r;
    reg read_bank_r;

    assign write_bank = write_bank_r;

    always @(posedge wr_clk) begin
        if (rst) begin
            write_bank_r <= 1'b1;
            read_bank_r  <= 1'b0;
            frame_ready  <= 1'b0;
        end
        else begin
            if (wr_en) begin
                if (write_bank_r)
                    mem1[wr_addr] <= wr_data;
                else
                    mem0[wr_addr] <= wr_data;
            end

            if (wr_commit) begin
                read_bank_r  <= write_bank_r;
                write_bank_r <= ~write_bank_r;
                frame_ready  <= 1'b1;
            end
        end
    end

    assign rd_data = rd_en ?
                     (read_bank_r ? mem1[rd_addr] : mem0[rd_addr]) :
                     24'd0;

endmodule
