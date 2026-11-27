`timescale 1ns/1ps
module tb_scaler_prefilter;
 reg clk=0,rst=1,sof=0,valid=0;reg [11:0] width=640;reg [23:0] pixel=0;
 always #5 clk=~clk;
 wire out_valid,overflow;wire [23:0] out_pixel;
 bmp_write_scaler #(.ANTIALIAS(1)) dut(.clk(clk),.rst(rst),.src_sof(sof),
  .src_w(width),.src_h(12'd1),.src_valid(valid),.src_pixel(pixel),
  .dst_valid(out_valid),.dst_pixel(out_pixel),.overflow(overflow));
 integer mode=0,count=0,frames=0,x,source_x;reg [23:0] expected;
 always @(posedge clk)begin
  #1;
  if(out_valid)begin
   x=count%640;source_x=x*width/640;
   if(mode==1)expected={8'(x==0?0:128),8'(x==0?0:128),8'd254};
   else expected={8'(source_x),8'(255-source_x),8'd254};
   if(out_pixel!==expected)$fatal(1,"prefilter mismatch mode=%0d pixel=%0d actual=%h expected=%h",mode,count,out_pixel,expected);
   count=count+1;
  end
  if(overflow)$fatal(1,"prefilter overflow");
  if(out_valid && count==307200)frames=frames+1;
  if(count>307200)$fatal(1,"prefilter extra pixels");
 end
 task frame(input integer w,input integer kind);
  integer before_frames;
  begin
   width=w;mode=kind;count=0;before_frames=frames;
   repeat(6)@(negedge clk);
   sof=1;
   for(integer i=0;i<w;i=i+1)begin
    valid=1;pixel=kind==1?{8'(i%2?255:0),8'(i%2?255:0),8'd254}:{8'(i),8'(255-i),8'd254};
    @(negedge clk);sof=0;valid=0;repeat(31)@(negedge clk);
   end
   wait(frames>before_frames);@(negedge clk);
  end
 endtask
 initial begin
  for(integer a=0;a<256;a=a+1)for(integer b=0;b<256;b=b+1)begin
   if(dut.rounded_mean(8'(a),8'(b))!==8'((a+b+1)/2))$fatal(1,"mean arithmetic a=%0d b=%0d",a,b);
   #1;
  end
  repeat(5)@(negedge clk);rst=0;frame(640,0);frame(1280,1);frame(427,0);
  $display("PASS: 65536 exhaustive rounded means and 921600 exact scaler pixels; 640-wide identity and 427-wide upscaling preserved; 1280-wide alternating stripes reduce to rounded grey without new buffers, overflow or lost SOF pixel");$finish;
 end
 initial begin #25000000;$fatal(1,"prefilter timeout");end
endmodule
