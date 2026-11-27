`timescale 1ns/1ps
module tb_temperature_wave_equivalence;
 reg clk=0;always #6.666 clk=~clk;
 reg rst=1;reg [11:0] x=0,y=0;reg [9:0] injected=0;
 reg [23:0] sample=0;reg sample_valid=0,frame_tick=0;
 integer phase=0,cycles=0,checks=0,live_checks=0;reg [1023:0] covered=0;
 genvar g;
 generate for(g=0;g<2;g=g+1)begin: variant
  wire [23:0] rgb,old_rgb;wire [7:0] alpha,old_alpha;
  audio_waveform_precise_overlay #(.WAVE_W(g==0?384:256),.WAVE_H(160),.WAVE_Y(g==0?130:150),.POINT_PX(g==0?2:4),.SAMPLE_STEP(3)) dut(
   .clk(clk),.rst(rst),.frame_tick(frame_tick),.audio_sample_valid(sample_valid),.audio_sample(sample),.x(x),.y(y),.wave_rgb(rgb),.wave_alpha(alpha));
  temperature_parent_wave #(.WAVE_W(g==0?384:256),.WAVE_H(160),.WAVE_Y(g==0?130:150),.POINT_PX(g==0?2:4),.SAMPLE_STEP(3)) reference(
   .clk(clk),.rst(rst),.frame_tick(frame_tick),.audio_sample_valid(sample_valid),.audio_sample(sample),.x(x),.y(y),.wave_rgb(old_rgb),.wave_alpha(old_alpha));
  initial begin
   force dut.sample_d=injected;force reference.sample_d=injected;
   force dut.cap_display_valid=1'b1;force reference.cap_display_valid=1'b1;
   wait(phase==1);
   release dut.sample_d;release reference.sample_d;
   release dut.cap_display_valid;release reference.cap_display_valid;
  end
  always @(posedge clk)begin #1;
   if(!rst)begin
    if({rgb,alpha,dut.raw_wave_y,dut.raw_wave_y_r,dut.wave_y,dut.wave_y_r}!==
       {old_rgb,old_alpha,reference.raw_wave_y,reference.raw_wave_y_r,reference.wave_y,reference.wave_y_r})
     $fatal(1,"wave register equivalence variant%0d phase%0d cycle%0d sample%h x%0d y%0d got%h/%h raw%h expected%h/%h raw%h",g,phase,cycles,injected,x,y,rgb,alpha,dut.raw_wave_y,old_rgb,old_alpha,reference.raw_wave_y);
    checks++;
    if(phase==1&&dut.cap_display_valid)live_checks++;
   end
  end
 end endgenerate
 task scan(input integer count);
 integer n;
 begin
  for(n=0;n<count;n=n+1)begin
   @(negedge clk);cycles++;x=n%1280;y=(n/1280)%720;
   injected=cycles%1024;sample={{3{injected[9]}},injected,11'd0};
   sample_valid=cycles%3==0;frame_tick=x==0&&y==0;
   if(phase==0)covered[injected]=1;
  end
 end endtask
 initial begin
  repeat(6)@(negedge clk);rst=0;scan(1280*720);
  @(negedge clk);rst=1;phase=1;frame_tick=0;
  repeat(6)@(negedge clk);rst=0;scan(2*1280*720);
  @(negedge clk);
  if(&covered!==1'b1||checks<5529000||live_checks<1800000)$fatal(1,"wave coverage %0d/%0d allraw=%b",checks,live_checks,&covered);
  $display("PASS: waveform register relocation exact per-cycle raw/history/RGB/alpha %0d comparisons, all1024 ten-bit samples, %0d unforced live capture comparisons, POINT_PX2/4, resets and three full1280x720 scans",checks,live_checks);$finish;
 end
endmodule
