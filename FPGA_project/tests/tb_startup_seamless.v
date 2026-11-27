`timescale 1ns/1ps
// Full production scanout -> compositor -> AXIS, with the same independent
// source qualification as the board. No HDMI encrypted-core/sink model.
module tb_startup_seamless;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg memory_ready=0,image=0,starve=0,load=1,nearly=1;
 wire req,hs,vs,de,source_pixel_ready;wire[23:0] source_rgb;
 video_scanout_720p scan(.clk(clk),.rst(rst),.read_req(req),
  .read_req_ack(req&&memory_ready),.read_en(),.read_data(32'h13579b00),
  .read_empty(!memory_ready||starve),.hs(hs),.vs(vs),.de(de),.rgb(source_rgb),
  .pixel_ready(source_pixel_ready),.raw_hs(),.raw_vs(),.raw_de(),
  .raw_frame_start(),.raw_x(),.raw_y());
 wire oh,ov,od;wire[23:0] rgb;wire[11:0] ox,oy;
 wire qualified,output_reset,video_ready,axis_valid;wire[23:0] axis_rgb;
 wire axis_ready=!output_reset;reg locked=0;integer lock_cycles=0;
 always@(posedge clk or posedge output_reset)
  if(output_reset)begin locked<=0;lock_cycles<=0;end
  else if(lock_cycles==30)locked<=1;else lock_cycles<=lock_cycles+1;
 hdmi_startup_guard #(.SETTLE_FRAMES(2),.UNLOCK_FRAMES(8),.BAD_FRAMES(3)) guard(
  .clk(clk),.async_reset(rst),.memory_ready(memory_ready),.frame_sync(ov),
  .video_locked(locked),.image_complete(image),.axis_valid(axis_valid),
  .axis_ready(axis_ready),.output_reset(output_reset),.video_ready(video_ready));
 startup_display_qualifier qualifier(.clk(clk),.rst(rst),.image_complete(image),
  .normal_active(1'b1),.frame_sync(vs),.pixel_de(de),
  .pixel_ready(source_pixel_ready),.hdmi_ready(video_ready),.display_ready(qualified));
 smart_terminal_overlay_pipelined #(.ENABLE_STARTUP_UI(1),.USE_COLOUR_PALETTE(1),
  .ENHANCED_AUDIO_VIS(1),.WAVE_W(384),.WAVE_H(160),.POINT_PX(2),.SAMPLE_STEP(3),
  .EXTERNAL_SPECTRUM(1),.EXTERNAL_MAP_PIXELS(1),.REMOTE_MAP(1),
  .SCREEN_W(1280),.SCREEN_H(720)) ui(
  .clk(clk),.rst(rst),.i_hs(hs),.i_vs(vs),.i_de(de),.i_rgb(source_rgb),
  .emergency(1'b0),.startup_loading(!qualified),.startup_progress(qualified?9'd511:9'd0),
  .emergency_event(2'd0),.load_in_flight(load),.load_nearly_done(nearly),
  .fx_sel(3'd3),.fx_off(1'b0),.audio_mag(16'd0),.audio_sample_valid(1'b0),
  .audio_sample(24'd0),.external_band_valid(1'b0),.external_spectrum_live(1'b0),
  .external_band_data(20'd0),.map_live(1'b0),.map_scene(188'd0),.map_frame_tick(),
  .map_pixels_valid(1'b0),.map_pixels_stale(1'b0),.page_index(3'd2),
  .brightness(3'd4),.contrast(3'd4),.interval_selection(2'd0),.playback_running(1'b1),
  .palette_bank(2'd0),.palette_write_enable(1'b0),.palette_write_address(10'd0),
  .palette_write_value(8'd0),.feature_mask(4'b0010),.src_w(16'd640),.src_h(16'd480),
  .o_hs(oh),.o_vs(ov),.o_de(od),.o_rgb(rgb),.o_x(ox),.o_y(oy));
 video_rgb_to_axis_720p bridge(.I_clk(clk),.I_rst(output_reset),.I_vs(ov),
  .I_de(od),.I_rgb(rgb),.O_video_user(),.O_video_valid(axis_valid),
  .O_video_last(),.O_video_data(axis_rgb));
 integer frames=0,pixels=0,full_frames=0,loading_frames=0,photo_frames=0;
 integer checked_loading=0,checked_photo=0,bar_pixels=0,resets=0;
 reg prev_vs=0,prev_reset=1,frame_loading=1,have_active=0;
 // Check an independent interior region, away from all OSD/plot regions.
 // All loading pixels are opaque, all first-photo pixels have exact RGB.
 always@(posedge clk)begin
  #1;
  if(!rst)begin
   if(!prev_reset&&output_reset)resets=resets+1;
   if(ov&&!prev_vs)begin
    frames=frames+1;
    if(have_active)begin
     if(pixels!=921600)$fatal(1,"Blank/truncated output frame: %0d",pixels);
     full_frames=full_frames+1;
     if(frame_loading)loading_frames=loading_frames+1;else photo_frames=photo_frames+1;
    end
    pixels=0;have_active=0;
   end
   if(od)begin
    if(!have_active)begin frame_loading=ui.startup_wait;have_active=1;end
    if(ui.startup_wait!==frame_loading)$fatal(1,"Loading UI changed during active frame");
    pixels=pixels+1;
    if(ox>=600&&ox<1100&&oy>=230&&oy<300)begin
     if(frame_loading)begin
      if(rgb!==24'h08182c)$fatal(1,"Loading background exposed source/black %h",rgb);
      checked_loading=checked_loading+1;
     end else begin
      if(rgb!==24'h13579b)$fatal(1,"First photo has black/faded/partial pixel %h",rgb);
      checked_photo=checked_photo+1;
     end
    end
    if(frame_loading&&ox>=450&&ox<830&&oy>=385&&oy<395)begin
     if(rgb!==24'h203a52)$fatal(1,"Waiting progress bar vanished %h",rgb);
     bar_pixels=bar_pixels+1;
    end
   end
  end
  prev_vs=ov;prev_reset=output_reset;
 end
 task next_frame;begin @(posedge vs);repeat(20)@(negedge clk);end endtask
 integer i;
 initial begin
  repeat(8)@(negedge clk);rst=0;memory_ready=1;
  // HDMI may qualify the loading screen, but a complete photo is still absent.
  for(i=0;i<7;i=i+1)begin next_frame;if(qualified)$fatal(1,"No photo nevertheless released loading UI");end
  image=1;starve=1;
  for(i=0;i<3;i=i+1)begin next_frame;if(qualified)$fatal(1,"Incomplete source scan released loading UI");end
  starve=0;
  wait(qualified);
  // Even a stale nearly-done flag must not impose a first-photo black fade.
  for(i=0;i<3;i=i+1)next_frame;
  load=0;nearly=0;
  for(i=0;i<3;i=i+1)next_frame;
  if(resets!=0||loading_frames<8||photo_frames<4||checked_loading<200000||checked_photo<100000||bar_pixels<10000)
   $fatal(1,"Insufficient seamless coverage loading=%0d photo=%0d resets=%0d",loading_frames,photo_frames,resets);
  $display("PASS: full720p seamless loading-to-first-photo; %0d full921600-pixel frames, %0d loading frames, %0d photo frames; %0d opaque loading pixels, %0d exact first-photo pixels, %0d persistent progress-bar pixels; no image-triggered output reset; absent/incomplete source holds loading; stale near-done cannot blacken first photo",full_frames,loading_frames,photo_frames,checked_loading,checked_photo,bar_pixels);
  $finish;
 end
 initial begin #350000000;$fatal(1,"Seamless timeout frames=%0d",frames);end
endmodule
