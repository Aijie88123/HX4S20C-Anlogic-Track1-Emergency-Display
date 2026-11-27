`timescale 1ns/1ps
module tb_animation_kind;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,vs=0,emergency=0,requested=1,complete=0,kind=1;reg [1:0] event_id=3,incoming=0;
 wire mode,ready,display_slot; reg previous_slot;integer tick=0;
 map_received_frame_control #(.NORMAL_ANIMATION(1)) dut(.clk(clk),.rst(rst),.vsync(vs),.emergency(emergency),.event_type(event_id),
  .complete(complete),.incoming_event(incoming),.incoming_animation(kind),.animation_requested(requested),.commit_ready(ready),
  .staging_slot(),.display_slot(display_slot),.map_mode(mode),.have_map());
 always @(negedge clk)begin tick=tick+1;vs=tick%20<3;end
 task deliver(input k,input [1:0] e);
  begin @(negedge clk);kind=k;incoming=e;complete=1;wait(ready);@(posedge clk);@(negedge clk);complete=0;repeat(25)@(negedge clk);end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;
  deliver(1,0);if(!mode)$fatal(1,"normal animation hidden");
  emergency=1;requested=0;repeat(25)@(negedge clk);if(mode)$fatal(1,"stale animation shown as emergency map");
  deliver(0,3);if(!mode)$fatal(1,"emergency event3 map hidden");
  previous_slot=display_slot;event_id=1;
  repeat(100)begin @(negedge clk);if(!mode||display_slot!=previous_slot)$fatal(1,"old map dropped while waiting");end
  deliver(0,2);if(!mode||display_slot!=previous_slot)$fatal(1,"stale event published");
  deliver(0,1);if(!mode||display_slot==previous_slot)$fatal(1,"requested map did not swap");
  previous_slot=display_slot;event_id=2;repeat(25)@(negedge clk);event_id=0;
  deliver(0,2);if(!mode||display_slot!=previous_slot)$fatal(1,"rapid key stale event published");
  deliver(0,0);if(!mode||display_slot==previous_slot)$fatal(1,"latest event not published");
  emergency=0;requested=1;repeat(25)@(negedge clk);if(mode)$fatal(1,"stale emergency map shown as normal animation");
  deliver(1,0);if(!mode)$fatal(1,"animation return hidden");
  requested=0;repeat(25)@(negedge clk);if(mode)$fatal(1,"prelude did not suppress raster");
  $display("PASS: cached frame kind separates normal animation from emergency map, including emergency event3, with VS-only complete-frame swaps");$finish;
 end
 initial begin #100000;$fatal(1,"kind test timeout");end
endmodule
