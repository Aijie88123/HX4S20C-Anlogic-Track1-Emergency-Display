`timescale 1ns/1ps
module tb_native_vga_cancel;
 reg clk=0,rst=1,full=0,done=0;always #10 clk=~clk;
 wire req,en,cancel,valid;wire [31:0] data;integer count=0,complete=0;
 b_map_frame_renderer_vga dut(.clk(clk),.rst(rst),.enabled(1'b1),.particle_mode(1'b1),.animation_run(1'b1),.scene_valid(1'b0),.scene(188'd0),
  .frame_animation(),.motion_phase(),.write_req(req),.write_ack(req),.write_full(full),.write_done_toggle(done),.write_en(en),.write_data(data),.write_cancel(cancel),
  .frame_valid(valid),.frame_event(),.frame_consumed(1'b0));
 always @(posedge clk)begin
  if(req || rst)count<=0;
  else if(en)begin
   if(full || count>=115200)$fatal(1,"native writer overrun or full write");
   count<=count+1;if(count==115199)begin done<=~done;complete<=complete+1;end
  end
  if(valid && count!=115200)$fatal(1,"partial native frame advertised");
 end
 initial begin
  repeat(8)@(negedge clk);rst=0;
  wait(count==17);@(negedge clk);full=1;wait(cancel);repeat(4)@(negedge clk);full=0;
  wait(valid);if(complete!=1)$fatal(1,"aborted frame published");
  @(negedge clk);rst=1;#1;if(!cancel || valid)$fatal(1,"disconnect/reset did not cancel immutable frame owner");
  repeat(8)@(negedge clk);rst=0;wait(valid);
  if(complete!=2)$fatal(1,"native frame did not recover after reset count=%0d complete=%0d",count,complete);
  $display("PASS: native RGB444 writer FIFO-full abort, no partial-frame publish, reset cancellation and full115200-word restart");$finish;
 end
 initial begin #100000000;$fatal(1,"native cancellation timeout");end
endmodule
