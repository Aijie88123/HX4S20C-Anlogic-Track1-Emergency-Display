`timescale 1ns/1ps
module tb_realtime_worker;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,enabled=0,mode=1,run_animation=1,consume=0,full=0;
 wire req,wen,cancel,valid,frame_animation;wire [31:0] data;wire [8:0] motion;reg ack=0,done=0;
 integer words=0,requests=0,cancels=0;reg req_d=0;
 b_map_frame_renderer #(.CLK_HZ(6000),.FRAME_PERIOD(100),.PARTICLE_PAGE(1)) dut(
  .clk(clk),.rst(rst),.enabled(enabled),.particle_mode(mode),.animation_run(run_animation),.scene_valid(1'b1),.scene(188'd0),
  .write_req(req),.write_ack(ack),.write_full(full),.write_done_toggle(done),.write_en(wen),.write_data(data),.write_cancel(cancel),
  .frame_valid(valid),.frame_event(),.frame_consumed(consume),.frame_animation(frame_animation),.motion_phase(motion));
 always @(posedge clk)begin
  ack<=req;req_d<=req;
  if(req && !req_d)begin words<=0;requests<=requests+1;end
  if(cancel)begin words<=0;cancels<=cancels+1;end
  else if(wen)begin words<=words+1;if(words==(frame_animation?28927:115199))done<=~done;end
 end
 task clocks(input integer n);repeat(n)@(negedge clk);endtask
 task release_frame;begin consume=1;clocks(10);consume=0;clocks(10);end endtask
 integer old_requests;reg [8:0] frozen;
 initial begin
  clocks(8);rst=0;enabled=1;wait(words==500);@(negedge clk);full=1;clocks(2);full=0;
  wait(cancel);if(valid)$fatal(1,"partial overflow frame published");wait(valid);
  if(!frame_animation || words!=28928 || cancels==0)$fatal(1,"overflow recovery/complete length");
  run_animation=0;clocks(3);frozen=motion;old_requests=requests;clocks(1000);
  if(motion!=frozen || requests!=old_requests || !valid || words!=28928)$fatal(1,"held/paused frame mutated");
  release_frame;clocks(1000);if(valid || requests!=old_requests || motion!=frozen)$fatal(1,"paused worker restarted");
  run_animation=1;wait(valid);if(!frame_animation || words!=28928)$fatal(1,"resume did not produce complete frame");
  // In-flight particle frame remains typed/immutable across emergency entry.
  mode=0;clocks(100);if(!frame_animation || words!=28928)$fatal(1,"emergency retagged held particle frame");
  release_frame;wait(valid);if(frame_animation || words!=115200)$fatal(1,"map buffer did not regain full original length");
  enabled=0;old_requests=requests;release_frame;clocks(1000);if(valid || requests!=old_requests)$fatal(1,"offline worker generated another frame");
  mode=1;enabled=1;wait(valid);if(!frame_animation || words!=28928)$fatal(1,"reconnect particle mode failed");
  $display("PASS: B worker overflow cancel/recovery, complete aligned particle frames, immutable hold, paused trajectory and no new requests, resume, emergency mode change without frame retagging, original 115200-word map frames, offline quiescence/reconnect");$finish;
 end
 initial begin #20000000;$fatal(1,"worker timeout state %d words %d",dut.state,words);end
endmodule
