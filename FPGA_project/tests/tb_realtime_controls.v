`timescale 1ns/1ps
module tb_realtime_controls;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,kn=1,ka=1,em=0,vs=0,inc=0,map_visible=0;
 reg [2:0] role=0;wire cr,dv,fade,auto_play,map_ready,animation,animation_ready;wire [2:0] page;wire [4:0] feedback;
 a_media_cached_control #(.CLK_FREQ_HZ(1000),.FADE_MS(16),.EMER_DWELL_MS(100),.IMAGE_ROLES(8),.EMER_SEQUENCE(1),
  .STRICT_ORDER(1),.STRICT_PRELUDE(1),.FIXED_SLOTS(1),.NORMAL_ANIMATION(1),.PRIME_PAUSED_ANIMATION(1)) dut(
  .clk(clk),.rst(rst),.key_next(kn),.key_auto(ka),.emergency(em),.vsync(vs),.remote_phase(9'd0),.animation_visible(map_visible),
  .incoming_complete(inc),.incoming_role(role),.incoming_w(16'd640),.incoming_h(16'd480),.incoming_commit_ready(cr),
  .staging_slot(),.display_slot(),.display_valid(dv),.page_index(page),.disp_src_w(),.disp_src_h(),.disp_src_toggle(),.disp_audio_emergency(),
  .load_nearly_done(fade),.load_visual_active(),.auto_play_en_out(auto_play),.carousel_feedback(feedback),.interval_selection(),
  .brightness_step_toggle(),.contrast_step_toggle(),.cached_roles(),.state_code(),.emergency_map_ready(map_ready),
  .normal_animation(animation),.normal_animation_ready(animation_ready));
 integer ticks=0,i,start;reg saw_fade=0;
 always @(negedge clk)begin ticks=ticks+1;vs=ticks%20<2;if(fade)saw_fade=1;end
 task clocks(input integer n);repeat(n)@(negedge clk);endtask
 task image(input [2:0] n);begin role=n;inc=1;do @(posedge clk);while(!cr);@(negedge clk);inc=0;clocks(24);end endtask
 task next_key;begin saw_fade=0;kn=0;clocks(10);kn=1;clocks(90);if(!saw_fade)$fatal(1,"manual fade missing");end endtask
 task pause_key;begin ka=0;clocks(10);ka=1;clocks(30);end endtask
 initial begin
  clocks(4);rst=0;for(i=7;i>=0;i=i-1)image(i);
  pause_key;if(auto_play)$fatal(1,"pause failed");
  for(i=3;i<=7;i=i+1)begin next_key;if(page!=i || animation)$fatal(1,"manual still skipped %d",i);end
  next_key;if(!animation || !animation_ready || auto_play || !feedback[2] || !fade)$fatal(1,"paused first particle page not primed/faded");
  map_visible=1;clocks(10);if(feedback[2] || fade)$fatal(1,"paused animation failed to stop after complete frame");
  clocks(4000);if(page!=7 || !animation)$fatal(1,"paused particle page wrapped");
  em=1;wait(page==0);if(animation)$fatal(1,"emergency did not preempt particles");wait(page==1);wait(map_ready);clocks(20);
  em=0;wait(page==7);clocks(40);if(!animation || auto_play)$fatal(1,"emergency did not restore paused particle page");
  next_key;map_visible=0;if(page!=2 || animation)$fatal(1,"S2 cannot leave particle page");
  pause_key;if(!auto_play)$fatal(1,"resume failed");
  for(i=3;i<=7;i=i+1)begin wait(page==i);if(animation)$fatal(1,"automatic still skipped %d",i);end
  wait(animation);clocks(40);if(!animation_ready || !fade)$fatal(1,"automatic particle page not armed");
  map_visible=1;clocks(20);if(fade || !feedback[2])$fatal(1,"running particle feedback incorrect");
  clocks(10000);if(page!=7 || !animation)$fatal(1,"automatic animation returned to 01");
  pause_key;if(auto_play || feedback[2])$fatal(1,"animation S3 pause failed");pause_key;if(!auto_play || !feedback[2])$fatal(1,"animation S3 resume failed");
  next_key;if(page!=2 || animation)$fatal(1,"running S2 wrap failed");
  $display("PASS: ordinary six-image order then persistent real particle page, manual browsing with fades, S2 wrap, S3 pause/resume, first complete frame priming while paused, 05/06 emergency preemption and paused-page restore; no TF reload/key round trip");$finish;
 end
 initial begin #1000000;$fatal(1,"control timeout page %d animation %b",page,animation);end
endmodule
