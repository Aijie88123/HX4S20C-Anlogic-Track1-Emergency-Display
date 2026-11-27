`timescale 1ns/1ps
module tb_manual_controls;
 reg clk=0,rst=1,vs=0,emergency=0,next_key=1,auto_key=1,incoming=0,online=1,animation_visible=0;
 always #5 clk=~clk;
 integer ticks=0,requests=0,commits=0;reg [2:0] role=2;
 wire ready,valid,animation,map_ready,autoplay,epoch,bright,contrast;
 wire [2:0] page,display,staging;wire [5:0] cached;wire [4:0] feedback;
 reg [8:0] phase=0;
 a_media_cached_control #(.CLK_FREQ_HZ(1000),.IMAGE_ROLES(6),.EMER_SEQUENCE(1),.STRICT_PRELUDE(1),.STRICT_ORDER(1),.NORMAL_ANIMATION(1),.EMER_DWELL_MS(80),.PRIME_PAUSED_ANIMATION(1)) dut(
  .animation_visible(animation_visible),
  .clk(clk),.rst(rst),.key_next(next_key),.key_auto(auto_key),.emergency(emergency),.vsync(vs),.remote_phase(phase),
  .incoming_complete(incoming),.incoming_role(role),.incoming_w(16'd640),.incoming_h(16'd480),.incoming_commit_ready(ready),
  .staging_slot(staging),.display_slot(display),.display_valid(valid),.page_index(page),.disp_src_w(),.disp_src_h(),.disp_src_toggle(epoch),.disp_audio_emergency(),
  .load_nearly_done(),.load_visual_active(),.auto_play_en_out(autoplay),.carousel_feedback(feedback),.interval_selection(),
  .brightness_step_toggle(bright),.contrast_step_toggle(contrast),.cached_roles(cached),.state_code(),.emergency_map_ready(map_ready),.normal_animation(animation));
 always @(negedge clk)begin
  ticks=ticks+1;vs=ticks%20<3;
  phase={online,2'b0,1'b1,2'b0,feedback[4] && dut.elapsed>=3000,feedback[4] && dut.elapsed>=2840,feedback[0]};
 end
 reg [2:0] prior_page=2;reg prior_animation=0,prior_epoch=0,allowed=0;
 always @(posedge clk)begin
  allowed=dut.commit_edge;
  #1;
  if(!rst)begin
   if(page!=prior_page && !allowed)$fatal(1,"manual page moved outside VS");
   if(page<2 && !emergency && !dut.em_sync[2] && !dut.mode_pending && !dut.mode_change)$fatal(1,"alarm image selected during normal browsing");
   if(animation && page!=4)$fatal(1,"animation covers another local page");
   if(epoch!=prior_epoch)commits=commits+1;
  end
  prior_page=page;prior_animation=animation;prior_epoch=epoch;
 end
 task deliver(input [2:0] r);begin
  @(negedge clk);role=r;incoming=1;wait(ready);@(posedge clk);@(negedge clk);incoming=0;repeat(20)@(negedge clk);
 end endtask
 task press_next;integer start_tick;begin
  @(negedge clk);next_key=0;repeat(12)@(negedge clk);start_tick=ticks;next_key=1;
  repeat(35)@(negedge clk);
  if(dut.manual_pending)$fatal(1,"cached manual request did not finish within 35ms of release");
 end endtask
 task pause_toggle;begin
  @(negedge clk);auto_key=0;repeat(12)@(negedge clk);auto_key=1;repeat(35)@(negedge clk);
 end endtask
 reg [17:0] held_slots;integer old_commits;
 initial begin
  repeat(5)@(negedge clk);rst=0;
  deliver(2);deliver(3);deliver(4);deliver(0);deliver(1);
  wait(animation);animation_visible=1;repeat(20000)@(negedge clk);
  if(page!=4 || !autoplay)$fatal(1,"automatic sequence did not stay in animation");
  held_slots={dut.slot[5],dut.slot[4],dut.slot[3],dut.slot[2],dut.slot[1],dut.slot[0]};
  pause_toggle;if(autoplay || feedback[2])$fatal(1,"S3 pause not exported to B");
  old_commits=commits;repeat(5000)@(negedge clk);
  if(!animation || page!=4 || commits!=old_commits)$fatal(1,"pause blanked/restarted cached animation");
  press_next;if(page!=2 || animation || autoplay)$fatal(1,"paused animation ->01");
  press_next;if(page!=3 || animation)$fatal(1,"01->02");
  press_next;if(page!=4 || animation)$fatal(1,"02->03");
  press_next;if(page!=4 || !animation || autoplay)$fatal(1,"03->animation while paused");
  if(held_slots!={dut.slot[5],dut.slot[4],dut.slot[3],dut.slot[2],dut.slot[1],dut.slot[0]})$fatal(1,"manual browsing swapped/reloaded cached frames");
  pause_toggle;if(!autoplay || !feedback[2])$fatal(1,"S3 resume not exported");
  press_next;if(page!=2 || animation)$fatal(1,"playing animation ->01");
  wait(page==3);wait(page==4);wait(animation);repeat(10000)@(negedge clk);
  if(page!=4)$fatal(1,"auto wrapped after manual browsing");
  // Manual local browsing still works if the B link disappears.
  online=0;pause_toggle;press_next;if(page!=2 || animation)$fatal(1,"offline local cache browse");
  @(negedge clk);next_key=0;repeat(1450)@(negedge clk);next_key=1;repeat(35)@(negedge clk);
  if(!bright || page!=2)$fatal(1,"S2 long hold changed page instead of brightness");
  @(negedge clk);auto_key=0;repeat(1450)@(negedge clk);auto_key=1;repeat(35)@(negedge clk);
  if(!contrast || autoplay)$fatal(1,"S3 long hold toggled playback instead of contrast");
  emergency=1;wait(page==0);if(map_ready)$fatal(1,"map preceded05");
  wait(page==1);if(map_ready)$fatal(1,"map preceded06");wait(map_ready);
  emergency=0;wait(animation && page==4);repeat(25)@(negedge clk);
  if(autoplay)$fatal(1,"emergency return lost user pause choice");
  // A first paused visit must prime one frame instead of leaving03 displayed.
  @(negedge clk);rst=1;animation_visible=0;repeat(5)@(negedge clk);rst=0;online=1;
  deliver(2);deliver(3);deliver(4);pause_toggle;
  press_next;press_next;press_next;
  if(page!=4 || !animation || autoplay || !feedback[2])$fatal(1,"paused first animation visit did not request a complete frame");
  animation_visible=1;repeat(5)@(negedge clk);
  if(autoplay || feedback[2])$fatal(1,"first-frame preparation changed user pause choice");
  $display("PASS: real debounced S2/S3, <=35ms scaled cached switch, auto01/02/03/animation no-wrap, repeated manual wrap, pause/resume feedback, cache slots retained, offline browse, long-hold B/C, emergency05/06/map and return to animation; first paused animation visit primes a complete frame then stops");$finish;
 end
 initial begin #2000000;$fatal(1,"manual test timeout page=%d animation=%b pending=%b",page,animation,dut.manual_pending);end
endmodule
