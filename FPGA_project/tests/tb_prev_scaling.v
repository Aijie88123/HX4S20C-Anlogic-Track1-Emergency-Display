`timescale 1ns/1ps
module tb_prev_scaling #(parameter W=320,H=240);
 reg clk=0,rst=1,sof=0,valid=0;reg [23:0] source=0;
 always #10 clk=~clk;
 wire out_valid,overflow;wire [23:0] out;
 bmp_write_scaler #(.ANTIALIAS(1)) dut(.clk(clk),.rst(rst),.src_w(12'(W)),.src_h(12'(H)),
  .src_sof(sof),.src_valid(valid),.src_pixel(source),.dst_valid(out_valid),.dst_pixel(out),.overflow(overflow));
 function [23:0] pattern(input integer x,y);
  begin pattern={8'((x*13+y*7)^31),8'(x*3+y*19),8'((x^y)*5)};end
 endfunction
 integer pixels=0,xx,yy,waits;localparam PERIOD=(W>=320&&H>=240)?24:96;
 reg [23:0] expected,prior;integer sx,sy,c;
 always @(negedge clk)if(!rst)begin
  if(overflow)$fatal(1,"FAIL: normalization overrun W=%d H=%d period=%d pixels=%d",W,H,PERIOD,pixels);
  if(out_valid)begin
   sx=(pixels%640)*W/640;sy=(pixels/640)*H/480;expected=pattern(sx,sy);
   if(W>640 && sx>0)begin
    prior=pattern(sx-1,sy);
    for(c=0;c<3;c=c+1)expected[c*8+:8]=8'((integer'(expected[c*8+:8])+integer'(prior[c*8+:8])+1)/2);
   end
   if(out!==expected)$fatal(1,"FAIL: boundary pixel W=%d H=%d out=%d got=%h expected=%h",W,H,pixels,out,expected);
   pixels=pixels+1;
  end
 end
 initial begin
  repeat(8)@(negedge clk);rst=0;repeat(8)@(negedge clk);
  for(yy=0;yy<H;yy=yy+1)for(xx=0;xx<W;xx=xx+1)begin
   @(posedge clk);#1;source=pattern(xx,yy);valid=1;sof=(xx==0&&yy==0);
   @(posedge clk);#1;valid=0;sof=0;
   repeat(PERIOD-2)@(posedge clk);
  end
  waits=0;
  while(pixels<307200 && waits<2000000)begin @(posedge clk);waits=waits+1;end
  if(pixels!=307200)$fatal(1,"FAIL: incomplete boundary output pixels=%d",pixels);
  $display("PASS: normalization pacing boundary %0dx%0d, source pixel period=%0d clocks, 307200 independent normalized pixels, zero overflow",W,H,PERIOD);
  $finish;
 end
endmodule
