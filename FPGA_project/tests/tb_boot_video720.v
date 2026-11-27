`timescale 1ns/1ps
module tb_boot_video720;
 reg refclk=0,video_clk=0,rst_n=1;always #10 refclk=~refclk;always #6.666 video_clk=~video_clk;
 wire startup_hold,por;board_startup_reset #(.STABLE_CYCLES(8)) boot(.ref_clk(refclk),.rst_n(rst_n),.clock_locks(3'b111),.reset_hold(startup_hold));
 startup_release_sync release_video(.clk(video_clk),.async_fault(!rst_n),.startup_hold(startup_hold),.rst(por));
 reg mem_clk=0;always #4 mem_clk=~mem_clk;
 wire mem_reset;startup_release_sync #(.STAGES(16)) release_mem(.clk(mem_clk),.async_fault(!rst_n),.startup_hold(startup_hold),.rst(mem_reset));
 wire req,hs,vs,de,pixel_ready;wire [23:0] rgb;
 video_scanout_720p scan(.clk(video_clk),.rst(por),.read_req(req),.read_req_ack(req&&!mem_reset),.read_en(),
  .read_data(32'h13579b00),.read_empty(mem_reset),.hs(hs),.vs(vs),.de(de),.rgb(rgb),.pixel_ready(pixel_ready),
  .raw_hs(),.raw_vs(),.raw_de(),.raw_frame_start(),.raw_x(),.raw_y());
 reg image_complete=0,drop=0;wire outreset,video_ready;wire axis_valid,axis_user,axis_last;wire [23:0] axis_rgb;
 wire axis_ready=!outreset&&!drop;reg locked=0;integer lock_wait=0;
 always @(posedge video_clk or posedge outreset)
  if(outreset)begin locked<=0;lock_wait<=0;end
  else if(lock_wait==40)locked<=1;else lock_wait<=lock_wait+1;
 hdmi_startup_guard #(.SETTLE_FRAMES(3),.UNLOCK_FRAMES(8),.BAD_FRAMES(2)) guard(
  .clk(video_clk),.async_reset(por),.memory_ready(!mem_reset),.frame_sync(vs),.video_locked(locked),
  .image_complete(image_complete),.axis_valid(axis_valid),.axis_ready(axis_ready),.output_reset(outreset),.video_ready(video_ready));
 video_rgb_to_axis_720p bridge(.I_clk(video_clk),.I_rst(outreset),.I_vs(vs),.I_de(de),.I_rgb(rgb),
  .O_video_user(axis_user),.O_video_valid(axis_valid),.O_video_last(axis_last),.O_video_data(axis_rgb));
 wire qualified;startup_display_qualifier qualifier(.clk(video_clk),.rst(por),.image_complete(image_complete),
  .normal_active(1'b1),.frame_sync(vs),.pixel_de(de),.pixel_ready(pixel_ready),.hdmi_ready(video_ready),.display_ready(qualified));
 integer exact_pixels=0,frames=0,restarts=0;reg prev_vs=0,prev_reset=1;
 always @(posedge video_clk)begin
  if(!por)begin
   if(vs&&!prev_vs)frames<=frames+1;
   if(axis_valid&&axis_ready)begin
    if(axis_rgb!==24'h13579b)$fatal(1,"Actual scanout/AXIS RGB mismatch %h",axis_rgb);
    exact_pixels<=exact_pixels+1;
   end
   if(!prev_reset&&outreset)restarts<=restarts+1;
   if(restarts>2)$fatal(1,"Unexpected recurring output reset");
  end
  prev_vs<=vs;prev_reset<=outreset;
 end
 task next_frame;begin @(posedge vs);repeat(8)@(negedge video_clk);end endtask
 integer i;
 initial begin
  wait(!por);next_frame;next_frame;next_frame;
  image_complete=1;
  wait(qualified);repeat(8)@(negedge video_clk);
  if(restarts!=0)$fatal(1,"First image interrupted healthy output");
  for(i=0;i<3;i=i+1)begin next_frame;if(!qualified)$fatal(1,"Healthy full720p frame lost qualification");end
  drop=1;next_frame;if(video_ready)$fatal(1,"Unaccepted real720p pixels qualified");
  next_frame;wait(outreset);drop=0;
  wait(qualified);next_frame;
  if(!image_complete || restarts!=1 || exact_pixels<8*1280*720)$fatal(1,"No cache-preserving full720p recovery pixels=%0d resets=%0d",exact_pixels,restarts);
  $display("PASS: actual1280x720 scanout and RGB-to-AXIS, exact RGB pixels=%0d frames=%0d; configuration without reset-key pulse, no first-image output reset, two rejected real frames and cache-preserving automatic output recovery",exact_pixels,frames);$finish;
 end
 initial begin #700000000;$fatal(1,"Full720p integration timeout frame=%0d",frames);end
endmodule
