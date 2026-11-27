module tb_hdmi_startup_guard;
 parameter SETTLE=16,UNLOCK=180;
 reg clk=0,rst=1,ready=0,vs=0,locked=0;
 always #5 clk=~clk;
 wire reset,video_ready;reg axis_valid=0;
 hdmi_startup_guard #(.SETTLE_FRAMES(SETTLE),.UNLOCK_FRAMES(UNLOCK),.ACTIVE_PIXELS(4)) dut(
 .clk(clk),.async_reset(rst),.memory_ready(ready),.frame_sync(vs),.video_locked(locked),.image_complete(1'b0),.axis_valid(axis_valid),.axis_ready(1'b1),.output_reset(reset),.video_ready(video_ready));
 task tick_frame;begin @(negedge clk);vs=1;axis_valid=0;repeat(4)@(negedge clk);vs=0;axis_valid=1;repeat(4)@(negedge clk);axis_valid=0;end endtask
 integer i,resets=0;reg oldreset=1;
 always @(posedge clk)begin #1;
  if(!rst&&reset!=oldreset&& !vs && ready)$fatal(1,"Output reset changed outside VS");
  if(!oldreset&&reset)resets=resets+1;
  oldreset=reset;
 end
 initial begin
 repeat(4)@(negedge clk);rst=0;
 for(i=0;i<4;i=i+1)begin tick_frame;if(!reset)$fatal(1,"Released before memory ready");end
 ready=1;repeat(5)@(negedge clk);
 for(i=1;i<SETTLE;i=i+1)begin tick_frame;if(!reset)$fatal(1,"Released before settle interval");end
 tick_frame;if(reset)$fatal(1,"Did not release at settled VS");
 // A late sink locks before the watchdog: no unnecessary pulse.
 for(i=0;i<UNLOCK-2;i=i+1)begin tick_frame;if(reset)$fatal(1,"Premature lock watchdog");end
 locked=1;repeat(4)@(negedge clk);
 for(i=0;i<UNLOCK+4;i=i+1)begin tick_frame;if(reset)$fatal(1,"Reset a healthy output");end
 locked=0;repeat(4)@(negedge clk);
 for(i=1;i<UNLOCK;i=i+1)begin tick_frame;if(reset)$fatal(1,"Unlock timeout too short");end
 tick_frame;if(!reset)$fatal(1,"Missing lock did not recover output");
 for(i=1;i<SETTLE;i=i+1)begin tick_frame;if(!reset)$fatal(1,"Recovery release too early");end
 tick_frame;if(reset)$fatal(1,"Recovery did not release");
 locked=1;repeat(4)@(negedge clk);tick_frame;
 // PLL disturbance is an immediate output-only reset; ready must settle again.
 @(negedge clk);ready=0;rst=1;#1;if(!reset)$fatal(1,"Asynchronous PLL reset did not assert");
 repeat(4)@(negedge clk);rst=0;
 for(i=0;i<3;i=i+1)begin tick_frame;if(!reset)$fatal(1,"Restarted with memory unavailable");end
 ready=1;repeat(5)@(negedge clk);
 for(i=1;i<SETTLE;i=i+1)tick_frame;
 tick_frame;if(reset)$fatal(1,"Second cold start failed");
 $display("PASS: HDMI-only startup/reset after memory ready, %0d complete VS boundaries, no healthy-output resets, %0d-frame unlock recovery, PLL disturbance and second cold start",SETTLE,UNLOCK);$finish;
 end
 initial begin #1000000;$fatal(1,"Guard timeout");end
endmodule
