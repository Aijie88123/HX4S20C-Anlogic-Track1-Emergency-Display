`timescale 1ns/1ps
module tb_slow_carousel_control;
 parameter integer SELECTED_MS=3000;
 localparam [1:0] SELECTION=SELECTED_MS==5000?1:SELECTED_MS==8000?2:0;
 reg clk=0,rst=1,online=1;always #5 clk=~clk;
 reg [10:0] scan_cycle=0;always @(posedge clk)if(rst)scan_cycle<=0;else if(scan_cycle==1662)scan_cycle<=0;else scan_cycle<=scan_cycle+1'b1;
 wire vs=scan_cycle<10,fs=scan_cycle==10;
 reg incoming=0;reg [2:0] incoming_role=0;wire commit_ready;wire [7:0] phase;
 wire [4:0] feedback;wire [2:0] page,slot;wire valid,commit_toggle,normal_animation;reg [2:0] selector=1;
 distributed_carousel_clock #(.CLK_FREQ_HZ(100000),.PERIOD0_MS(3000),.PERIOD1_MS(5000),.PERIOD2_MS(8000),.STARTUP_PERIOD_MS(3000)) timing(
  .clk(clk),.rst(rst),.switches(SELECTION),.period_step(1'b0),.online(online),.feedback(feedback),.actual_emergency(1'b0),.phase(phase));
 a_media_cached_control #(.CLK_FREQ_HZ(100000),.NORMAL_PERIOD_MS(3000),.IMAGE_ROLES(8),.FIXED_SLOTS(1),.EMER_SEQUENCE(1),.STRICT_PRELUDE(1),.STRICT_ORDER(1),.NORMAL_ANIMATION(1),.PRIME_PAUSED_ANIMATION(1)) control(
  .clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),.emergency(1'b0),.vsync(vs),.remote_phase({online,phase}),.animation_visible(normal_animation),
  .incoming_complete(incoming),.incoming_role(incoming_role),.incoming_w(16'd640),.incoming_h(16'd480),.incoming_commit_ready(commit_ready),
  .display_slot(slot),.display_valid(valid),.page_index(page),.disp_src_toggle(commit_toggle),.carousel_feedback(feedback),.normal_animation(normal_animation));
 wire active,flip;wire [5:0] animation_phase;wire [2:0] old_slot,new_slot;
 photo_geometry_control #(.PHASE_STEP(2)) geometry(.clk(clk),.rst(rst),.frame_start(fs),.eligible(valid&&!normal_animation),
  .selector(selector),.slot_in(slot),.commit_toggle(commit_toggle),.active(active),.flip(flip),.phase(animation_phase),.old_slot(old_slot),.new_slot(new_slot));
 integer cycles=0,episode_frames=0,episodes=0,commits=0,first_commit=0,last_commit=0,mode,role;reg last_toggle=0,was_active=0,sampled_fs;
 reg [5:0] prev_phase=0;reg [2:0] held_old,held_new;
 always @(posedge clk)begin
  sampled_fs=fs;cycles=cycles+1;#1;
  if(rst)begin episode_frames=0;episodes=0;commits=0;last_toggle=0;was_active=0;first_commit=0;last_commit=0;end
  else begin
   if(valid && commit_toggle!=last_toggle)begin
    if(commits==0)first_commit=cycles;
    else if(!normal_animation)begin
     if(active)$fatal(1,"automatic page commit overtook active geometry");
     if(commits==1)begin if(cycles-first_commit<300000 || cycles-first_commit>303400)$fatal(1,"first image dwell changed");end
     // The free-running millisecond divider can contribute a partial first
     // millisecond; display commits then quantize to the next VS boundary.
     else if(cycles-last_commit<(SELECTED_MS-1)*100 || cycles-last_commit>(SELECTED_MS+34)*100)$fatal(1,"slow page cadence wrong %0d",cycles-last_commit);
    end
    last_commit=cycles;commits=commits+1;
   end
   last_toggle=commit_toggle;
   if(sampled_fs)begin
    if(active)begin
     if(!was_active)begin episode_frames=0;held_old=old_slot;held_new=new_slot;end
     else if(animation_phase!=prev_phase+2)$fatal(1,"not step2");
     if(old_slot!=held_old || new_slot!=held_new)$fatal(1,"active image pair overwritten");
     episode_frames=episode_frames+1;prev_phase=animation_phase;
    end else if(was_active)begin
     if(episode_frames!=17 || prev_phase!=32)$fatal(1,"not full17-phase geometry count=%0d last=%0d",episode_frames,prev_phase);
     episodes=episodes+1;
    end
    was_active=active;
   end
  end
 end
 task run_mode(input [2:0] effect);begin
  @(negedge clk);rst=1;incoming=0;selector=effect;repeat(20)@(negedge clk);rst=0;
  for(role=0;role<8;role=role+1)begin
   @(negedge clk);incoming_role=role;incoming=1;wait(commit_ready);@(posedge clk);@(negedge clk);incoming=0;
   wait(!commit_ready);
  end
  wait(normal_animation);repeat(2000)@(negedge clk);
  if(episodes!=5 || page!=7)$fatal(1,"missing photo transitions or animation prelude: episodes=%0d page=%0d",episodes,page);
  $display("PASS: effect=%0d production A+B control, all8 complete roles, first3s then selected slow automatic cadence, five complete17-phase effects, immutable pairs and existing animation-page entry",effect);
 end endtask
 initial begin run_mode(1);run_mode(2);$finish;end
 initial begin #200000000;$fatal(1,"fast control timeout page=%0d commits=%0d episodes=%0d",page,commits,episodes);end
endmodule
