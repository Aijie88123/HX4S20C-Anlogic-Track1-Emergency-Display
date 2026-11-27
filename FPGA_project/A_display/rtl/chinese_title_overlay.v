`timescale 1ns/1ps

module chinese_title_overlay #(
    parameter integer SCREEN_W = 1280,
    parameter integer SCREEN_H = 720
) (
    input  wire [11:0] x,
    input  wire [11:0] y,

    output reg  [23:0] title_rgb,
    output reg  [7:0]  title_alpha
);

    localparam integer TITLE_CHARS = 13;
    localparam integer GLYPH_W = 32;
    localparam integer GLYPH_H = 32;
    localparam integer TITLE_X = (SCREEN_W - (TITLE_CHARS * GLYPH_W)) / 2;
    localparam integer TITLE_Y = 14;
    localparam integer BAR_LEFT = TITLE_X - 16;
    localparam integer BAR_RIGHT = TITLE_X + (TITLE_CHARS * GLYPH_W) + 16;
    localparam integer BAR_TOP = TITLE_Y - 8;
    localparam integer BAR_BOTTOM = TITLE_Y + GLYPH_H + 8;

    wire in_bar = (x >= BAR_LEFT) && (x < BAR_RIGHT) &&
                  (y >= BAR_TOP) && (y < BAR_BOTTOM);
    wire in_glyph = (x >= TITLE_X) && (x < (TITLE_X + TITLE_CHARS * GLYPH_W)) &&
                    (y >= TITLE_Y) && (y < (TITLE_Y + GLYPH_H));

    wire [11:0] rel_x = x - TITLE_X;
    wire [11:0] rel_y = y - TITLE_Y;
    wire [3:0]  char_index = rel_x[8:5];
    wire [4:0]  glyph_col = rel_x[4:0];
    wire [4:0]  glyph_row = rel_y[4:0];
    wire [31:0] row_bits;
    wire glyph_pixel = in_glyph && row_bits[31-glyph_col];

    chinese_title_rom u_chinese_title_rom (
        .char_index (char_index),
        .row_index  (glyph_row),
        .row_bits   (row_bits)
    );

    always @(*) begin
        if (glyph_pixel) begin
            title_rgb   = 24'hFFFFFF;
            title_alpha = 8'd255;
        end
        else if (in_bar) begin
            title_rgb   = 24'h0B2A4A;
            title_alpha = 8'd120;
        end
        else begin
            title_rgb   = 24'h000000;
            title_alpha = 8'd0;
        end
    end

endmodule

// The optional second stage separates the glyph-bit selection from the
// host's aux-layer selection. Supply coordinates one stage earlier when
// REGISTER_OUTPUT is enabled to preserve the host's pixel alignment.
module chinese_title_overlay_pipelined #(
    parameter integer SCREEN_W = 1280,
    parameter integer SCREEN_H = 720,
    parameter integer REGISTER_OUTPUT = 0
) (
    input wire clk,
    input wire rst,
    input wire [11:0] x,
    input wire [11:0] y,
    output reg [23:0] title_rgb,
    output reg [7:0] title_alpha
);
    localparam integer TITLE_CHARS = 13;
    localparam integer TITLE_X = (SCREEN_W - TITLE_CHARS * 32) / 2;
    localparam integer TITLE_Y = 14;
    wire in_bar_pre = (x >= TITLE_X - 16) &&
                      (x < TITLE_X + TITLE_CHARS * 32 + 16) &&
                      (y >= TITLE_Y - 8) && (y < TITLE_Y + 32 + 8);
    wire in_glyph_pre = (x >= TITLE_X) && (x < TITLE_X + TITLE_CHARS * 32) &&
                        (y >= TITLE_Y) && (y < TITLE_Y + 32);
    wire [11:0] rel_x = x - TITLE_X;
    wire [11:0] rel_y = y - TITLE_Y;
    wire [31:0] row_bits;
    reg [4:0] column_q;
    reg in_bar_q, in_glyph_q;
    reg [23:0] title_rgb_c;
    reg [7:0] title_alpha_c;

    chinese_title_rom_sync u_font (
        .clk(clk), .char_index(rel_x[8:5]), .row_index(rel_y[4:0]),
        .row_bits(row_bits)
    );
    always @(posedge clk) begin
        if(rst)begin
            column_q <= 5'd0;
            in_bar_q <= 1'b0;
            in_glyph_q <= 1'b0;
        end else begin
            column_q <= rel_x[4:0];
            in_bar_q <= in_bar_pre;
            in_glyph_q <= in_glyph_pre;
        end
    end
    always @(*) begin
        if(in_glyph_q && row_bits[31-column_q])begin
            title_rgb_c = 24'hFFFFFF;
            title_alpha_c = 8'd255;
        end else if(in_bar_q)begin
            title_rgb_c = 24'h0B2A4A;
            title_alpha_c = 8'd120;
        end else begin
            title_rgb_c = 24'd0;
            title_alpha_c = 8'd0;
        end
    end
    generate
        if (REGISTER_OUTPUT != 0) begin : g_registered_output
            always @(posedge clk) begin
                if (rst) begin
                    title_rgb <= 24'd0;
                    title_alpha <= 8'd0;
                end else begin
                    title_rgb <= title_rgb_c;
                    title_alpha <= title_alpha_c;
                end
            end
        end else begin : g_combinational_output
            always @(*) begin
                title_rgb = title_rgb_c;
                title_alpha = title_alpha_c;
            end
        end
    endgenerate
endmodule
