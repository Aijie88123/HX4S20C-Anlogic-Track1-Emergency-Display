`timescale 1ns/1ps
module tb_particle_commit_cdc;
 reg clk=0,source_clk=0,rst=1;always #6.666 clk=~clk;always #20 source_clk=~source_clk;
 reg [5:0] count=0;always @(posedge clk)if(rst)count<=0;else count<=count+1'b1;
 wire vs=count<5,fs=count==10;reg [2:0] source_slot=2;reg commit_toggle=0;
 particle_transition_probe d(.video_clk(clk),.rst_all(rst),.sw(4'd1),.display_slot(source_slot),.disp_src_toggle(commit_toggle),
  .emergency_mode(1'b0),.emergency_event(2'd0),.normal_animation_ready_video(2'd0),.map_cdc_valid(1'b0),.map_commit_event(2'd0),.map_commit_animation(1'b1),
  .map_cdc_ready(),.map_staging_slot(),.map_display_slot(),.map_mode(),.map_display_animation(),.map_have(),
  .video_read_req(),.video_read_en(),.video_read_req_ack(1'b0),.video_read_empty(1'b1),.video_read_data(32'd0),.read_base(),.read_len(),.hs(),.vs(),.de(),.vout_data_raw());
 initial begin force d.raw_vs=vs;force d.raw_frame_start=fs;end
 integer episodes=0;reg was_active=0;
 always @(posedge clk)if(fs)begin #1;if(!rst)begin if(was_active && !d.photo_geometry_active)episodes=episodes+1;was_active=d.photo_geometry_active;end end
 task source_commit;input [2:0] target;
  begin @(negedge source_clk);source_slot=target;commit_toggle=~commit_toggle;repeat(8)@(negedge source_clk);end
 endtask
 initial begin
  repeat(10)@(negedge clk);rst=0;repeat(4)@(posedge vs);
  // Source-bus activity without a commit must never select a page.
  repeat(3)begin
   @(negedge source_clk);source_slot=3;repeat(80)@(negedge source_clk);
   source_slot=4;repeat(80)@(negedge source_clk);source_slot=0;repeat(80)@(negedge source_clk);
   if(d.geometry_committed_photo!=2 || d.photo_geometry_active || episodes)$fatal(1,"uncommitted multibit slot leaked into video");
  end
  source_commit(6);wait(d.photo_geometry_active);
  if(d.photo_geometry_old!=2 || d.photo_geometry_new!=6)$fatal(1,"CDC did not select committed slot6");
  @(negedge source_clk);source_slot=1;repeat(80)@(negedge source_clk);
  if(d.geometry_committed_photo!=6 || d.photo_geometry_new!=6)$fatal(1,"active pair sampled uncommitted bus");
  source_commit(7);source_commit(3);
  wait(!d.photo_geometry_active);wait(d.photo_geometry_active);
  if(d.photo_geometry_old!=6 || d.photo_geometry_new!=3)$fatal(1,"latest coherent queued target lost");
  wait(!d.photo_geometry_active);repeat(4)@(posedge vs);
  if(episodes!=2 || d.geometry_current_source!=3 || d.photo_geometry_active)$fatal(1,"unexpected CDC transition");
  $display("PASS:25MHz source/75MHz video, existing three-stage commit CDC rejects uncommitted multibit slot activity across many frame boundaries; coherent active pair and latest queued target retained");$finish;
 end
 initial begin #2000000;$fatal(1,"CDC timeout");end
endmodule
