`timescale 1ns/1ps
module tb_mesh3d_owner;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,connected=0,enabled=1,particle=1,run_animation=1,scene_valid=0;
 reg [187:0] scene=0;reg mesh_valid=1;reg [7:0] mesh_count=118;reg [15:0] mesh_id=1;reg [12:0] mesh_meta=0;
 wire release_toggle;wire [10:0] geometry_address;reg [15:0] geometry_data;
 reg [223:0] triangles[0:353];wire animation;wire [8:0] phase;
 wire req,en,cancel,valid;wire [31:0] data;wire [1:0] event_type;
 reg ack=0,full=0,done_toggle=0,consumed=0;integer words=0,expected=0,requests=0,published=0;reg owned=0,held_type;
 reg [7:0] stall=0;reg [31:0] cycles=0;reg release_d=0;
 b_dual_scene_renderer #(.CLK_HZ(3000)) dut(.clk(clk),.rst(rst),.connected(connected),.enabled(enabled),.particle_mode(particle),.animation_run(run_animation),
  .scene_valid(scene_valid),.scene(scene),.mesh_valid(mesh_valid),.mesh_count(mesh_count),.mesh_id(mesh_id),.mesh_meta(mesh_meta),
  .release_toggle(release_toggle),.geometry_address(geometry_address),.geometry_data(geometry_data),.frame_animation(animation),.motion_phase(phase),
  .write_req(req),.write_ack(ack),.write_full(full),.write_done_toggle(done_toggle),.write_en(en),.write_data(data),.write_cancel(cancel),
  .frame_valid(valid),.frame_event(event_type),.frame_consumed(consumed));
 always @(posedge clk)begin
  cycles<=cycles+1;geometry_data<=triangles[geometry_address>>4]>>((geometry_address&15)*16);
  stall<=stall+1'b1;full<=owned&&!held_type && stall[3:0]>=12;
  release_d<=release_toggle;
  if(release_toggle!=release_d)mesh_valid<=0;
  if(cancel)begin owned<=0;ack<=0;words<=0;end
  else if(req && !owned)begin owned<=1;held_type<=animation;words<=0;expected<=animation?28928:115200;ack<=1;requests<=requests+1;end
  else if(owned)begin
   if(!req)ack<=0;
   if(en)begin
    // The tile writer sees the same ready edge as its FIFO. No registered
    // one-cycle-late write is allowed to slip through a full indication.
    if(full || animation!=held_type)$fatal(1,"FAIL: shared buffer overflow or ownership retag");
    if(words>=expected)$fatal(1,"FAIL: frame word overrun");
    words<=words+1;
    if(words+1==expected)done_toggle<=~done_toggle;
   end
   if(valid)begin if(words!=expected)$fatal(1,"FAIL: partial shared frame published %0d/%0d",words,expected);end
   if(valid && consumed)begin owned<=0;published<=published+1;end
  end
 end
 task consume;begin @(negedge clk);consumed=1;repeat(5)@(negedge clk);consumed=0;end endtask
 integer before_requests;reg [8:0] frozen;
 initial begin
  $readmemh("mesh3d_projected.hex",triangles);mesh_meta=triangles[0][196:184];repeat(8)@(negedge clk);rst=0;connected=1;
  @(negedge clk);scene_valid=1;@(negedge clk);scene_valid=0;
  wait(words==120);@(negedge clk);particle=0;
  wait(valid);if(!animation)$fatal(1,"FAIL: particle changed type on emergency entry");
  repeat(20)@(negedge clk);if(!valid||!animation)$fatal(1,"FAIL: frame retired before_requests A ACK");consume;
  wait(owned&&!held_type&&words>100);@(negedge clk);particle=1;
  wait(valid);if(animation)$fatal(1,"FAIL: 3D changed type on emergency exit");consume;
  wait(valid&&animation);run_animation=0;consume;
  repeat(20)@(negedge clk);before_requests=requests;frozen=phase;
  repeat(300)@(negedge clk);if(requests!=before_requests||phase!=frozen)$fatal(1,"FAIL: paused particle requested another frame or moved");
  run_animation=1;wait(owned&&held_type&&words>300);@(negedge clk);connected=0;
  repeat(50)@(negedge clk);if(valid||req||en||!cancel)$fatal(1,"FAIL: disconnected worker not quiescent");
  connected=1;wait(valid&&animation);consume;
  $display("PASS: real particle/3D worker arbitration, two immutable frame types through mode changes, FIFO backpressure, exact word counts, final ACK retirement, paused motion/no new requests, partial-frame cancellation and reconnect");$finish;
 end
 initial begin #250000000;$fatal(1,"FAIL: owner timeout owner=%b locked=%b pstate=%0d mstate=%0d words=%0d",dut.owner,dut.locked,dut.u_particles.state,dut.u_mesh.state,words);end
endmodule
