`timescale 1ns/1ps
module tb_mesh3d_camera_controls;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,kn=1,ka=1,em=0,vs=0,inc=0;reg [2:0] role=0;
 wire ready,map_ready;wire [1:0] camera;wire brightness,contrast;
 a_media_cached_control #(.CLK_FREQ_HZ(1000),.FADE_MS(16),.EMER_DWELL_MS(100),.IMAGE_ROLES(8),.EMER_SEQUENCE(1),
  .STRICT_ORDER(1),.STRICT_PRELUDE(1),.FIXED_SLOTS(1),.NORMAL_ANIMATION(1),.PRIME_PAUSED_ANIMATION(1)) dut(
  .clk(clk),.rst(rst),.key_next(kn),.key_auto(ka),.emergency(em),.vsync(vs),.remote_phase(9'd0),.animation_visible(1'b0),
  .incoming_complete(inc),.incoming_role(role),.incoming_w(16'd640),.incoming_h(16'd480),.incoming_commit_ready(ready),
  .brightness_step_toggle(brightness),.contrast_step_toggle(contrast),.map_view_mode(camera),.emergency_map_ready(map_ready));
 integer ticks=0,i;reg previous_b,previous_c;
 always @(negedge clk)begin ticks=ticks+1;vs=ticks%20<2;end
 task clocks(input integer n);repeat(n)@(negedge clk);endtask
 task short_next;begin kn=0;clocks(12);kn=1;clocks(40);end endtask
 initial begin
  clocks(4);rst=0;
  for(i=7;i>=0;i=i-1)begin role=i;inc=1;do @(posedge clk);while(!ready);@(negedge clk);inc=0;clocks(24);end
  short_next;if(camera!=0)$fatal(1,"FAIL: normal image S2 changed 3D camera");
  em=1;clocks(30);short_next;if(camera!=0)$fatal(1,"FAIL: emergency still-picture S2 changed camera");
  wait(map_ready);clocks(20);
  for(i=1;i<=4;i=i+1)begin short_next;if(camera!=i%4)$fatal(1,"FAIL: map camera cycle expected %0d got %0d",i%4,camera);end
  previous_b=brightness;kn=0;clocks(1450);kn=1;clocks(40);
  if(camera!=0 || brightness==previous_b)$fatal(1,"FAIL: S2 hold did not preserve brightness/camera separation");
  previous_c=contrast;ka=0;clocks(1450);ka=1;clocks(40);
  if(camera!=0 || contrast==previous_c)$fatal(1,"FAIL: S3 hold did not preserve contrast");
  short_next;if(camera!=1)$fatal(1,"FAIL: camera left mode");em=0;clocks(80);short_next;
  if(camera!=1)$fatal(1,"FAIL: ordinary S2 modified saved camera mode");
  $display("PASS: A S2 emergency-map short releases select auto/left/centre/right; ordinary browsing and emergency prelude do not rotate; S2/S3 long holds retain brightness/contrast without accidental camera commands");$finish;
 end
 initial begin #200000;$fatal(1,"FAIL: camera key timeout");end
endmodule
