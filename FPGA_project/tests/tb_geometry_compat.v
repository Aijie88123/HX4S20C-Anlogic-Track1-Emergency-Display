`timescale 1ns/1ps
module tb_geometry_compat;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [31:0] random_word=32'h583191ab,word_data=0;reg [31:0] cycles=0;
 wire req0,req1,en0,en1,empty0,empty1,word0,word1;
 wire [31:0] data0,data1;wire h0,v0,d0,p0,h1,v1,d1,p1;wire [23:0] rgb0,rgb1;
 wire word_empty=cycles%109<5;
 geometry_parent_unpack original_unpack(.clk(clk),.rst(rst),.restart(req0),.word_empty(word_empty),.word_data(word_data),.word_read(word0),.pixel_read(en0),.pixel_empty(empty0),.pixel_data(data0));
 rgb888_frame_unpack #(.FAST_WORD_READ(1)) new_unpack(.clk(clk),.rst(rst),.restart(req1),.fast_mode(1'b0),.word_empty(word_empty),.word_data(word_data),.word_read(word1),.pixel_read(en1),.pixel_empty(empty1),.pixel_data(data1));
 geometry_parent_scanout original(.clk(clk),.rst(rst),.read_req(req0),.read_req_ack(req0),.read_en(en0),.read_data(data0),.read_empty(empty0),.hs(h0),.vs(v0),.de(d0),.rgb(rgb0),.pixel_ready(p0),.raw_hs(),.raw_vs(),.raw_de(),.raw_x(),.raw_y(),.raw_frame_start());
 video_scanout_720p #(.ENABLE_GEOMETRY(1)) updated(.clk(clk),.rst(rst),.read_req(req1),.read_req_ack(req1),.read_en(en1),.read_data(data1),.read_empty(empty1),.hs(h1),.vs(v1),.de(d1),.rgb(rgb1),.pixel_ready(p1),.raw_hs(),.raw_vs(),.raw_de(),.raw_x(),.raw_y(),.raw_frame_start(),
  .geometry_active(1'b0),.geometry_flip(1'b0),.geometry_width(12'd0),.geometry_left(12'd0),.geometry_height(10'd0),.geometry_top(10'd0),.geometry_inv_x(17'd0),.geometry_inv_y(17'd0),.geometry_old_base(21'd0),.geometry_new_base(21'd0),.geometry_back_half(1'b0),.geometry_read_base());
 integer checks=0;
 always @(posedge clk)begin
  cycles<=cycles+1;random_word<={random_word[30:0],random_word[31]^random_word[21]^random_word[1]^random_word[0]};
  if(word0 && !word_empty)word_data<=random_word;
  #1;
  if(!rst)begin
   if({req0,en0,word0,empty0,data0,h0,v0,d0,p0,rgb0} !== {req1,en1,word1,empty1,data1,h1,v1,d1,p1,rgb1})$fatal(1,"normal path differs from exact trim at cycle %0d",cycles);
   checks=checks+1;
  end
 end
 initial begin repeat(10)@(negedge clk);rst=0;repeat(2600000)@(negedge clk);
  $display("PASS: exact trim normal-path compatibility %0d cycles: real RGB888 unpack and full720p scanout, geometry hardware enabled but inactive, randomized packed words and supply stalls, every FIFO request/control/RGB/pixel_ready output equal",checks);$finish;
 end
endmodule
