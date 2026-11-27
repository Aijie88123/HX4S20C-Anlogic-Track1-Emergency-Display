`timescale 1ns/1ps
module tb_photo_geometry_control;
 reg clk=0,rst=1,frame_start=0,eligible=0,toggle=0;always #5 clk=~clk;
 reg [2:0] selector=1,slot=2;
 wire active,flip,back,hold;wire [5:0] phase;wire [2:0] old_slot,new_slot,idle_slot;
 wire [11:0] width,left;wire [9:0] height,top;wire [16:0] ix,iy;
 photo_geometry_control dut(.clk(clk),.rst(rst),.frame_start(frame_start),.eligible(eligible),.selector(selector),
  .slot_in(slot),.commit_toggle(toggle),.active(active),.flip(flip),.phase(phase),.old_slot(old_slot),.new_slot(new_slot),
  .width(width),.height(height),.left(left),.top(top),.inv_x(ix),.inv_y(iy),.back_half(back),.idle_slot(idle_slot),.hold_slot(hold));
 integer i,sc,checks=0;
 task frame;begin @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;repeat(12)@(negedge clk);end endtask
 task commit;input [2:0] target;begin @(negedge clk);slot=target;toggle=~toggle;repeat(12)@(negedge clk);end endtask
 task check;input value;input [511:0] message;begin if(value!==1'b1)$fatal(1,"%0s phase=%0d active=%0d old=%0d new=%0d idle=%0d",message,phase,active,old_slot,new_slot,idle_slot);checks=checks+1;end endtask
 task geometry;input isflip;
 begin
  for(i=0;i<=32;i=i+1)begin
   check(active && flip==isflip && phase==i,"wrong complete-frame animation progression");
   sc=isflip?(i<16?32-2*i:2*i-32):i;
   check(width==40*sc && height==720*sc/32,"wrong aspect/width progression");
   check(left==(1280-width)/2 && top==(720-height)/2,"off-centre geometry");
   check(ix==(width?640*4096/width:0) && iy==(height?480*4096/height:0),"ROM reciprocal differs from independent integer reference");
   frame;
  end
  check(!active && hold,"animation did not release into its complete target slot");
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;commit(2);repeat(4)frame;
  check(!active && !hold,"startup geometry unexpectedly enabled");eligible=1;frame;
  check(!active && hold && idle_slot==2,"initial complete photo should not animate");
  commit(3);repeat(5)@(negedge clk);check(!active,"commit changed geometry midframe");frame;
  check(old_slot==2 && new_slot==3,"flip did not bind both immutable slots");geometry(1);
  check(idle_slot==3,"flip idle slot is not its final image");selector=2;commit(4);frame;geometry(0);
  check(idle_slot==4,"zoom idle slot is not its final image");
  selector=1;commit(5);frame;repeat(8)frame;commit(6);commit(7);
  check(new_slot==5 && old_slot==4,"rapid requests rewrote active pair");
  while(active)frame;
  check(idle_slot==5,"pending page exposed before completed target");frame;
  check(active && old_slot==5 && new_slot==7,"latest pending page not queued from completed target");
  eligible=0;frame;check(!active && !hold,"emergency/map/FX-off did not preempt at frame boundary");
  eligible=1;selector=2;frame;check(!active && idle_slot==7,"return should rearm without stale animation");
  commit(2);frame;check(active && !flip,"zoom did not restart after preemption");
  selector=3;frame;check(!active && !hold,"checkerboard selection retained geometry ownership");
  $display("PASS: geometry controller %0d assertions; first-image bypass, full 33-frame flip/zoom ROM/progression, coherent source commit, midframe invariance, immutable busy pair/latest queued target, emergency/map/FX-off and selector abort/rearm",checks);
  $finish;
 end
endmodule
