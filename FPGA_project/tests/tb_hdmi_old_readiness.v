`timescale 1ns/1ps
module tb_hdmi_old_readiness;
 reg clk=0,rst=1,mem=0,vs=0,lock=0;always #5 clk=~clk;
 wire old_reset,old_ready,new_reset,new_ready;
 legacy_hdmi_startup_guard #(.SETTLE_FRAMES(3),.UNLOCK_FRAMES(8)) old_guard(
  .clk(clk),.async_reset(rst),.memory_ready(mem),.frame_sync(vs),.video_locked(lock),.output_reset(old_reset),.video_ready(old_ready));
 hdmi_startup_guard #(.SETTLE_FRAMES(3),.UNLOCK_FRAMES(8),.BAD_FRAMES(3),.ACTIVE_PIXELS(12)) new_guard(
  .clk(clk),.async_reset(rst),.memory_ready(mem),.frame_sync(vs),.video_locked(lock),.image_complete(1'b0),
  .axis_valid(1'b1),.axis_ready(1'b0),.output_reset(new_reset),.video_ready(new_ready));
 task frame;begin @(negedge clk);vs=0;repeat(16)@(negedge clk);vs=1;repeat(2)@(negedge clk);vs=0;repeat(2)@(negedge clk);end endtask
 initial begin
  repeat(4)@(negedge clk);rst=0;mem=1;repeat(4)@(negedge clk);
  frame;frame;frame;if(old_reset || new_reset)$fatal(1,"Not released");
  lock=1;repeat(4)@(negedge clk);frame;
  if(!old_ready || new_ready)$fatal(1,"Lock-only false readiness was not reproduced");
  frame;frame;
  if(old_reset || !old_ready || !new_reset || new_ready)$fatal(1,"Output recovery difference missing");
  $display("PASS: exact parent lock-only guard reports ready with zero accepted pixels; new guard refuses readiness and restarts output under identical lock/memory/frame conditions");$finish;
 end
 initial begin #20000;$fatal(1,"Old/new readiness comparison timeout");end
endmodule
