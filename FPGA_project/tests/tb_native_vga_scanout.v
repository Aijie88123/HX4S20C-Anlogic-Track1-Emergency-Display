`timescale 1ns/1ps
module tb_native_vga_scanout;
 reg clk=0,rst=1,enabled=1,fs=0,hs=0,vs=0,de=0;always #6.666667 clk=~clk;
 reg [11:0] x=0,y=0;wire req,en,oh,ov,od;wire [23:0] out;
 reg [31:0] memory[0:115199],rd;integer pointer=0,checked=0,ix,iy,k;
 initial $readmemh("native_particle_words.hex",memory);
 map_rgb444_scanout dut(.clk(clk),.rst(rst),.enabled(enabled),.frame_start(fs),.animation(1'b1),
  .hs_raw(hs),.vs_raw(vs),.de_raw(de),.x_raw(x),.y_raw(y),.read_req(req),.read_ack(req),.read_empty(pointer>=115200),.read_data(rd),.read_en(en),.hs(oh),.vs(ov),.de(od),.rgb(out));
 reg [11:0] xd[0:4],yd[0:4];reg [4:0] dd=0;reg [95:0] group;reg [11:0] colour;reg [23:0] expected;
 integer word_base,sy;
 always @(posedge clk)begin
  if(req)pointer<=0;else if(en)begin rd<=memory[pointer];pointer<=pointer+1;end
  xd[0]<=x;yd[0]<=y;dd<={dd[3:0],de};for(k=1;k<5;k=k+1)begin xd[k]<=xd[k-1];yd[k]<=yd[k-1];end
  #1;
  if(!rst && od)begin
   sy=yd[4]*2/3;word_base=sy*240+(xd[4]/16)*3;
   group={memory[word_base+2],memory[word_base+1],memory[word_base]};colour=group>>(((xd[4]/2)%8)*12);
   expected={colour[11:8],colour[11:8],colour[7:4],colour[7:4],colour[3:0],colour[3:0]};
   if(out!==expected)$fatal(1,"native scanout x=%0d y=%0d got=%h expected=%h loaded=%0d",xd[4],yd[4],out,expected,dut.rows_loaded);
   checked=checked+1;
  end
 end
 initial begin
  repeat(8)@(negedge clk);rst=0;fs=1;@(negedge clk);fs=0;
  repeat(1500)@(negedge clk);
  for(iy=0;iy<720;iy=iy+1)begin
   y=iy;
   for(ix=0;ix<1650;ix=ix+1)begin x=ix;de=ix<1280;@(negedge clk);end
  end
  de=0;repeat(8)@(negedge clk);
  if(checked!=921600)$fatal(1,"display count=%0d",checked);
  $display("PASS: all921600 HDMI output pixels exactly match native640x480 RGB444 source, 3:2 row mapping, all480 native rows and all640 columns");$finish;
 end
endmodule
