`timescale 1ns/1ps
// Three independent synchronous read ports replace the existing S1 RGB register.
// No additional video latency. Only inactive mutable banks 1 and 2 are written.
module video_palette_lookup(
 input wire clk,rst,enable,
 input wire [23:0] in_rgb,
 input wire [1:0] bank,
 input wire write_enable,
 input wire [9:0] write_address,
 input wire [7:0] write_value,
 output reg [23:0] out_rgb
);
 reg [7:0] red[0:1023],green[0:1023],blue[0:1023];
 integer i;
 initial for(i=0;i<1024;i=i+1)begin red[i]=i[7:0];green[i]=i[7:0];blue[i]=i[7:0];end
 wire [1:0] read_bank=enable?bank:2'd0;
 wire [9:0] ra=rst?10'd0:{read_bank,in_rgb[23:16]};
 wire [9:0] ga=rst?10'd0:{read_bank,in_rgb[15:8]};
 wire [9:0] ba=rst?10'd0:{read_bank,in_rgb[7:0]};
 wire mutable_write=write_enable&&((write_address[9:8]==1)||(write_address[9:8]==2));
 always @(posedge clk)begin
  if(mutable_write)begin
   red[write_address]<=write_value;green[write_address]<=write_value;blue[write_address]<=write_value;
  end
  out_rgb<={red[ra],green[ga],blue[ba]};
 end
endmodule
