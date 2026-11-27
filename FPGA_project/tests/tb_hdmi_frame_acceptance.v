`timescale 1ns/1ps
module tb_hdmi_frame_acceptance;
 reg clk=0,rst=1,mem=0,vs=0,lock=0,image=0,valid=0,ready=1;
 always #5 clk=~clk;
 wire output_reset,video_ready;
 hdmi_startup_guard #(.SETTLE_FRAMES(3),.UNLOCK_FRAMES(5),.BAD_FRAMES(3),.ACTIVE_PIXELS(12)) dut(
  .clk(clk),.async_reset(rst),.memory_ready(mem),.frame_sync(vs),.video_locked(lock),
  .image_complete(image),.axis_valid(valid),.axis_ready(ready),.output_reset(output_reset),.video_ready(video_ready));
 integer resets=0;reg last_reset=1;
 always @(posedge clk)begin #1;
  if(!rst && last_reset!=output_reset && !vs && mem)$fatal(1,"Reset changed in an active line");
  if(!last_reset && output_reset)resets=resets+1;
  last_reset=output_reset;
 end
 task frame;input integer pixels;begin
  @(negedge clk);vs=0;valid=1;
  repeat(pixels)@(negedge clk);valid=0;
  repeat(2)@(negedge clk);vs=1;
  repeat(2)@(negedge clk);vs=0;
  repeat(2)@(negedge clk);
 end endtask
 task settle;integer i;begin
  for(i=0;i<3;i=i+1)frame(12);
  if(output_reset)$fatal(1,"Output failed to release after settle");
 end endtask
 task qualify;begin frame(12);if(video_ready)$fatal(1,"One frame qualified");frame(12);if(!video_ready)$fatal(1,"Two accepted full frames did not qualify");end endtask
 integer i,before_resets;
 initial begin
  repeat(4)@(negedge clk);rst=0;
  frame(12);if(!output_reset)$fatal(1,"Released without memory");
  mem=1;repeat(4)@(negedge clk);settle;
  lock=1;repeat(4)@(negedge clk);qualify;
  // Completing the image must not disturb an already qualified output.
  before_resets=resets;image=1;repeat(4)@(negedge clk);frame(12);
  if(output_reset || !video_ready || resets!=before_resets)$fatal(1,"Image completion interrupted HDMI");
  for(i=0;i<12;i=i+1)begin frame(12);if(output_reset || !video_ready)$fatal(1,"Healthy video was reset");end
  if(resets!=before_resets)$fatal(1,"Image completion repeated a reset");
  // Lock stays high although the core accepts no pixels: old lock-only
  // readiness stays high here. New qualification drops and retries output.
  ready=0;frame(12);if(video_ready)$fatal(1,"Rejected pixels still reported video ready");
  frame(12);frame(12);if(!output_reset)$fatal(1,"Locked but rejecting output did not recover");
  ready=1;settle;qualify;
  frame(7);if(video_ready)$fatal(1,"Partial frame qualified");
  frame(13);if(video_ready)$fatal(1,"Overlength frame qualified");
  frame(0);if(!output_reset)$fatal(1,"Malformed frames did not recover");
  settle;qualify;
  lock=0;repeat(4)@(negedge clk);if(video_ready)$fatal(1,"Lost lock still ready");
  for(i=0;i<5;i=i+1)frame(12);
  if(!output_reset)$fatal(1,"Lost-lock watchdog missing");
  settle;lock=1;repeat(4)@(negedge clk);qualify;
  $display("PASS: continuous output across first-image completion, two exact accepted frames, locked-but-rejecting retry, short/long/empty frame rejection, lock recovery, cached source retained and no healthy periodic reset; retries=%0d",resets);$finish;
 end
 initial begin #100000;$fatal(1,"Frame acceptance timeout");end
endmodule
