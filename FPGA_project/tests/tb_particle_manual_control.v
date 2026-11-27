`timescale 1ns/1ps
module tb_particle_manual_control;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [10:0] count=0;always @(posedge clk)if(rst)count<=0;else if(count==1662)count<=0;else count<=count+1'b1;
 wire vs=count<10,fs=count==10;
 reg next_key=1,auto_key=1,meta=0,dynamic_complete=0;reg [2:0] role=0;reg [3:0] selector=1;
 wire meta_ack,animation,animation_ready,autoplay,valid,photo_commit;wire [2:0] page,slot;wire [4:0] feedback;
 wire dyn_ack,staging,display,map_mode;wire req,en;wire [20:0] addr,len;
 a_media_cached_control #(.CLK_FREQ_HZ(100000),.NORMAL_PERIOD_MS(3000),.IMAGE_ROLES(8),.FIXED_SLOTS(1),.EMER_SEQUENCE(1),.STRICT_PRELUDE(1),.STRICT_ORDER(1),.NORMAL_ANIMATION(1),.PRIME_PAUSED_ANIMATION(1)) c(
  .clk(clk),.rst(rst),.key_next(next_key),.key_auto(auto_key),.emergency(1'b0),.vsync(vs),.remote_phase(9'd0),.animation_visible(map_mode),
  .incoming_complete(meta),.incoming_role(role),.incoming_w(16'd640),.incoming_h(16'd480),.incoming_commit_ready(meta_ack),
  .display_slot(slot),.disp_src_toggle(photo_commit),.display_valid(valid),.page_index(page),.normal_animation(animation),.normal_animation_ready(animation_ready),.auto_play_en_out(autoplay),.carousel_feedback(feedback));
 particle_transition_probe d(.video_clk(clk),.rst_all(rst),.sw(selector),.display_slot(slot),.disp_src_toggle(photo_commit),.emergency_mode(1'b0),.emergency_event(2'd0),
  .normal_animation_ready_video({2{animation_ready}}),.map_cdc_valid(dynamic_complete),.map_commit_event(2'd0),.map_commit_animation(1'b1),
  .map_cdc_ready(dyn_ack),.map_staging_slot(staging),.map_display_slot(display),.map_mode(map_mode),.map_display_animation(),.map_have(),
  .video_read_req(req),.video_read_en(en),.video_read_req_ack(req),.video_read_empty(1'b1),.video_read_data(32'd0),.read_base(addr),.read_len(len),.hs(),.vs(),.de(),.vout_data_raw());
 initial begin force d.raw_vs=vs;force d.raw_frame_start=fs;end
 integer episodes=0,particle_edges=0,nphase=0,phase_previous=0;reg was_active=0;reg [3:0] saved_old,saved_new;
 always @(posedge clk)begin
  if(fs)begin #1;
   if(rst)begin episodes=0;particle_edges=0;was_active=0;nphase=0;end
   else begin
    if(d.photo_geometry_active)begin
     if(!was_active)begin nphase=0;saved_old=d.photo_geometry_old;saved_new=d.photo_geometry_new;end
     else if(d.photo_geometry_phase!=phase_previous+2)$fatal(1,"manual phase skipped");
     if(saved_old!=d.photo_geometry_old || saved_new!=d.photo_geometry_new)$fatal(1,"manual pair changed");
     nphase=nphase+1;phase_previous=d.photo_geometry_phase;
    end else if(was_active)begin
     if(nphase!=17 || phase_previous!=32)$fatal(1,"manual transition incomplete %0d",nphase);
     episodes=episodes+1;if(saved_old[3]!=saved_new[3])particle_edges=particle_edges+1;
    end
    was_active=d.photo_geometry_active;
   end
  end
  if(!rst && dynamic_complete && d.freeze_dynamic_frame && dyn_ack)$fatal(1,"manual frozen commit lost");
 end
 task next_button;begin @(negedge clk);next_key=0;repeat(900)@(negedge clk);next_key=1;repeat(900)@(negedge clk);end endtask
 task completed_dynamic;begin @(negedge clk);dynamic_complete=1;wait(dyn_ack);@(posedge clk);@(negedge clk);dynamic_complete=0;end endtask
 task mode;input integer effect;integer r,p,mark;
 begin
  @(negedge clk);rst=1;meta=0;dynamic_complete=0;next_key=1;auto_key=1;selector=effect;
  repeat(30)@(negedge clk);episodes=0;particle_edges=0;was_active=0;nphase=0;rst=0;
  for(r=0;r<8;r=r+1)begin @(negedge clk);role=r;meta=1;wait(meta_ack);@(posedge clk);@(negedge clk);meta=0;end
  @(negedge clk);auto_key=0;repeat(900)@(negedge clk);auto_key=1;wait(!autoplay);repeat(900)@(negedge clk);
  for(p=3;p<=7;p=p+1)begin next_button;wait(page==p);wait(d.photo_geometry_active);wait(!d.photo_geometry_active);end
  if(animation || page!=7)$fatal(1,"animation prelude skipped");
  next_button;wait(animation);repeat(5)@(posedge vs);
  if(map_mode || d.photo_geometry_active || !feedback[2] || autoplay)$fatal(1,"paused late first particle behavior changed");
  completed_dynamic;wait(d.photo_geometry_active);
  fork begin completed_dynamic;end begin wait(!d.photo_geometry_active);end join
  repeat(3)@(posedge vs);mark=episodes;completed_dynamic;repeat(3)@(posedge vs);
  if(episodes!=mark || autoplay || !map_mode)$fatal(1,"steady paused dynamic swaps started transition or resumed PLAY");
  next_button;wait(page==2);wait(d.photo_geometry_active);
  // Queue the next manual photo while particle->photo2 is still active.
  next_button;wait(page==3);wait(!d.photo_geometry_active);wait(d.photo_geometry_active);wait(!d.photo_geometry_active);
  repeat(2)@(posedge vs);
  if(episodes!=8 || particle_edges!=2 || page!=3 || animation || autoplay || map_mode)$fatal(1,"manual sequence wrong episodes=%0d edges=%0d page=%0d",episodes,particle_edges,page);
  $display("PASS: actual A cached scheduler/manual key debounce effect=%0d, five photos then paused particle entry and wrap exit plus queued photo; eight immutable full17-phase episodes/two particle edges; late first frame/held complete/resume preserve PAUSE",effect);
 end endtask
 initial begin mode(1);mode(2);$finish;end
 initial begin #100000000;$fatal(1,"manual timeout page=%0d episodes=%0d animation=%b map=%b",page,episodes,animation,map_mode);end
endmodule
