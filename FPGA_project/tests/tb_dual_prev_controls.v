`timescale 1ns/1ps
module tb_dual_prev_controls;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,kn=1,ka=1,em=0,vs=0,inc=0,map_visible=0;
 reg [2:0] role=0;reg [15:0] iw=640,ih=480;
 wire cr,dv,fade,load,auto_play,map_ready;wire [2:0] stage,display,page;
 wire [15:0] dw,dh;wire [7:0] valid;wire epoch;
 a_media_cached_control #(.CLK_FREQ_HZ(1000),.FADE_MS(16),.EMER_DWELL_MS(100),
  .IMAGE_ROLES(8),.EMER_SEQUENCE(1),.STRICT_ORDER(1),.STRICT_PRELUDE(1),.FIXED_SLOTS(1)) dut(
  .clk(clk),.rst(rst),.key_next(kn),.key_auto(ka),.emergency(em),.vsync(vs),.remote_phase(9'd0),.animation_visible(map_visible),
  .incoming_complete(inc),.incoming_role(role),.incoming_w(iw),.incoming_h(ih),.incoming_commit_ready(cr),
  .staging_slot(stage),.display_slot(display),.display_valid(dv),.page_index(page),.disp_src_w(dw),.disp_src_h(dh),.disp_src_toggle(epoch),
  .disp_audio_emergency(),.load_nearly_done(fade),.load_visual_active(load),.auto_play_en_out(auto_play),
  .carousel_feedback(),.interval_selection(),.brightness_step_toggle(),.contrast_step_toggle(),.cached_roles(valid),.state_code(),
  .emergency_map_ready(map_ready),.normal_animation());
 integer ticks=0,i,commits=0;reg prev_epoch=0;
 always @(negedge clk)begin ticks=ticks+1;vs=ticks%20<2;end
 task clocks(input integer n);repeat(n)@(negedge clk);endtask
 task image(input [2:0] n);
  begin role=n;iw=n==5?427:n==6?800:n==7?1280:640;ih=n==5?321:n==6?600:n==7?720:480;
   inc=1;do @(posedge clk);while(!cr);@(negedge clk);inc=0;clocks(24);end
 endtask
 task next_key;begin kn=0;clocks(10);kn=1;clocks(65);end endtask
 task pause_key;begin ka=0;clocks(10);ka=1;clocks(30);end endtask
 task check_page(input integer n);
  begin if(page!=n || display!=n || !dv)$fatal(1,"FAIL: page/display expected=%0d got=%0d/%0d",n,page,display);
   if(dw!=(n==5?427:n==6?800:n==7?1280:640) || dh!=(n==5?321:n==6?600:n==7?720:480))$fatal(1,"FAIL: source resolution metadata");
  end
 endtask
 initial begin
  clocks(4);rst=0;
  for(i=7;i>=0;i=i-1)image(i);
  check_page(2);if(valid!=255)$fatal(1,"FAIL: eight complete roles");
  pause_key;if(auto_play)$fatal(1,"FAIL: S3 pause");
  for(i=3;i<=7;i=i+1)begin next_key;check_page(i);end
  next_key;check_page(2);
  clocks(3200);check_page(2);
  prev_epoch=epoch;image(2);if(epoch!=prev_epoch)$fatal(1,"FAIL: duplicate retransmission restarts displayed frame");
  pause_key;if(!auto_play)$fatal(1,"FAIL: S3 resume");
  for(i=3;i<=7;i=i+1)begin wait(page==i);check_page(i);end
  wait(page==2);check_page(2);
  em=1;wait(page==0);check_page(0);
  wait(fade);if(dut.elapsed<84)$fatal(1,"FAIL: early 05 fade");
  wait(page==1);check_page(1);
  wait(fade);if(dut.elapsed<84)$fatal(1,"FAIL: early 06 fade");
  wait(map_ready);if(dut.elapsed<100)$fatal(1,"FAIL: 06 dwell shortened");
  clocks(60);if(!fade)$fatal(1,"FAIL: preserve fade while waiting for full B map");
  map_visible=1;clocks(10);if(fade)$fatal(1,"FAIL: complete map did not begin fade in");
  em=0;map_visible=0;wait(page==2);check_page(2);
  // Late 06: keep the visible 05, then allow a complete fade window.
  rst=1;clocks(4);rst=0;image(2);image(0);em=1;
  wait(page==0);clocks(300);
  if(page!=0 || dut.emergency_stage!=0 || fade)$fatal(1,"FAIL: missing 06 prematurely left/faded the 05 image");
  role=1;iw=640;ih=480;inc=1;do @(posedge clk);while(!cr);@(negedge clk);inc=0;
  clocks(15);if(page!=0)$fatal(1,"FAIL: late 06 skipped its complete fade-out window");
  wait(page==1);if(dut.emergency_stage!=1)$fatal(1,"FAIL: 06 commit/stage mismatch");
  wait(map_ready);map_visible=1;clocks(10);
  $display("PASS: late 06 arrival after the alarm dwell keeps 05 visible, completes the entire fade-out interval, and commits 06 at the same VS as the emergency-stage transition");
  $display("PASS: six-page auto/manual ring, 640/427/800/1280 source OSD metadata, S3 pause/resume, immutable duplicate commit, 05->fade->06 full dwell->fade->complete B map and normal restore");$finish;
 end
 initial begin #2000000;$fatal(1,"FAIL: controls timeout page=%0d stage=%0d elapsed=%0d valid=%b",page,dut.emergency_stage,dut.elapsed,valid);end
endmodule
