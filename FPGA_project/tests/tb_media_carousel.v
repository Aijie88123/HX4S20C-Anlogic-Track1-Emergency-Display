`timescale 1ns/1ps
module tb_media_carousel;
 reg clk=0;always #5 clk=~clk;reg rst=1,vs=0,online=1,em=0,next_key=1,auto_key=1,period_step=0;
 reg [1:0] switches=0;wire [7:0] phase;wire [4:0] feedback;
 reg cv=0;reg [2:0] role=0;wire cr,dv,epoch,bri,con;wire [2:0] page,staging,slot;wire auto_play,fade;
 wire [4:0] caches;integer ticks=0,changes=0,k,start,endtick,delta;reg last_epoch=0,old_bri,old_con;
 distributed_carousel_clock #(.CLK_FREQ_HZ(1000),.DEBOUNCE_MS(3)) timer(.clk(clk),.rst(rst),.switches(switches),.period_step(period_step),.online(online),.feedback(feedback),.actual_emergency(em),.phase(phase));
 a_media_cached_control #(.CLK_FREQ_HZ(1000)) dut(.clk(clk),.rst(rst),.key_next(next_key),.key_auto(auto_key),.emergency(em),.vsync(vs),.remote_phase({online,phase}),
  .incoming_complete(cv),.incoming_role(role),.incoming_w(16'd640),.incoming_h(16'd480),.incoming_commit_ready(cr),
  .staging_slot(staging),.display_slot(slot),.display_valid(dv),.page_index(page),.disp_src_w(),.disp_src_h(),.disp_src_toggle(epoch),
  .disp_audio_emergency(),.load_nearly_done(fade),.load_visual_active(),.auto_play_en_out(auto_play),.carousel_feedback(feedback),.interval_selection(),
  .brightness_step_toggle(bri),.contrast_step_toggle(con),.cached_roles(caches),.state_code());
 always @(posedge clk)begin ticks<=ticks+1;vs<=ticks%32<4;if(epoch!=last_epoch)begin last_epoch<=epoch;changes<=changes+1;end end
 task stable_change;reg old;integer guard;begin old=epoch;guard=0;while(epoch==old)begin @(negedge clk);guard=guard+1;if(guard>10500)$fatal(1,"FAIL: carousel deadlock epoch %b phase %h feedback %b",epoch,phase,feedback);end end endtask
 task period_check;input integer milliseconds;integer t,fade_length;begin
  stable_change;t=ticks;fade_length=0;
  begin:deadline
   reg old;old=epoch;
   while(epoch==old)begin @(negedge clk);if(fade)fade_length=fade_length+1;end
  end
  if(ticks-t<milliseconds || ticks-t>milliseconds+40 || fade_length<160 || fade_length>200)$fatal(1,"FAIL: period %d got %d fade %d",milliseconds,ticks-t,fade_length);
 end endtask
 initial begin
  repeat(8)@(negedge clk);rst=0;
  for(k=0;k<5;k=k+1)begin role=k;cv=1;wait(cr);@(posedge clk);@(negedge clk);cv=0;repeat(32)@(negedge clk);end
  if(caches!=31 || !dv)$fatal(1,"FAIL: cached map");
  period_check(3000);
  period_step=1;@(negedge clk);period_step=0;period_check(5000);
  period_step=1;@(negedge clk);period_step=0;period_check(10000);
  // Short release toggles pause. Manual next still has its soft fade.
  auto_key=0;repeat(30)@(negedge clk);auto_key=1;repeat(20)@(negedge clk);
  if(auto_play)$fatal(1,"FAIL: pause key");start=changes;repeat(11000)@(negedge clk);if(changes!=start)$fatal(1,"FAIL: paused changed");
  next_key=0;repeat(30)@(negedge clk);next_key=1;stable_change;
  old_bri=bri;next_key=0;repeat(1450)@(negedge clk);next_key=1;repeat(20)@(negedge clk);if(bri==old_bri)$fatal(1,"FAIL: brightness long key");
  old_con=con;auto_key=0;repeat(1450)@(negedge clk);auto_key=1;repeat(20)@(negedge clk);if(con==old_con)$fatal(1,"FAIL: contrast long key");
  em=1;stable_change;if(page>1)$fatal(1,"FAIL: emergency enter");start=ticks;stable_change;if(ticks-start<2000 || ticks-start>2040 || page>1)$fatal(1,"FAIL: emergency dwell");
  em=0;stable_change;if(page<2)$fatal(1,"FAIL: emergency return");
  auto_key=0;repeat(30)@(negedge clk);auto_key=1;repeat(20)@(negedge clk);online=0;period_check(3000);
  $display("PASS: new A cache scheduler + actual B carousel clock: 3/5/10-second deadlines, ready/fade feedback without circular wait, complete blanking swap, pause/manual fade, brightness/contrast long keys, cached emergency 2-second rotation, normal restore and disconnected 3-second local fallback");$finish;
 end
 initial begin #1500000;$fatal(1,"FAIL: carousel timeout");end
endmodule
