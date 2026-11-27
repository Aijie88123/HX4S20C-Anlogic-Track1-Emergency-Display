`timescale 1ns/1ps
module tb_route_boot_equivalence;
reg clk=0,rst=1,vs=0,emergency=0,complete=0,requested=0,kind=0;reg[1:0]event_id=0,incoming=0;
wire[5:0]a,b;integer n=0;
always #5 clk=~clk;
map_received_frame_control #(.NORMAL_ANIMATION(1)) dut(.clk(clk),.rst(rst),.vsync(vs),.emergency(emergency),.event_type(event_id),.complete(complete),.incoming_event(incoming),.animation_requested(requested),.incoming_animation(kind),.staging_slot(a[0]),.display_slot(a[1]),.map_mode(a[2]),.have_map(a[3]),.display_animation(a[4]),.commit_ready(a[5]));
map_parent_reference #(.NORMAL_ANIMATION(1)) ref_dut(.clk(clk),.rst(rst),.vsync(vs),.emergency(emergency),.event_type(event_id),.complete(complete),.incoming_event(incoming),.animation_requested(requested),.incoming_animation(kind),.staging_slot(b[0]),.display_slot(b[1]),.map_mode(b[2]),.have_map(b[3]),.display_animation(b[4]),.commit_ready(b[5]));
initial begin
 repeat(200000)begin
 @(negedge clk);if(a!==b)$fatal(1,"boot/normal path differs at %d",n);
 n=n+1;rst=n%997==1;vs=n%32<3;complete=($random&7)==0;requested=$random;kind=$random;incoming=$random;event_id=$random;
 // Normal mode includes arbitrary pending/wrong-kind frames and repeated resets.
 emergency=0;
 end
 $display("PASS: 200000-cycle exact parent comparison of all map control outputs during boot/normal animation/reset/pending-frame cases");$finish;
end
endmodule
