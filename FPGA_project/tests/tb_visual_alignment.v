// Compare continuing media/OSD/audio outside intentional startup-UI changes.
// Full startup pixels and frame-boundary handoff are checked in tb_startup_seamless.
`timescale 1ns/1ps
module tb_visual_alignment;
reg clk=0;always #6.666667 clk=~clk;reg rst=1;wire hs,vs,de;wire[11:0]x,y;integer cycles=0,frames=0;reg oldvs=1;
wire [2:0] retained_fx=3'd3;
wire a_hs,a_vs,a_de,b_hs,b_vs,b_de;wire[11:0]a_x,a_y,b_x,b_y;wire[23:0]a_rgb,b_rgb;
video_scanout_720p timing(.clk(clk),.rst(rst),.read_req(),.read_req_ack(1'b0),.read_en(),.read_data(32'd0),.read_empty(1'b1),.hs(),.vs(),.de(),.rgb(),.raw_hs(hs),.raw_vs(vs),.raw_de(de),.raw_frame_start(),.raw_x(x),.raw_y(y));
always @(posedge clk)if(rst)begin cycles<=0;frames<=0;oldvs<=vs;end else begin cycles<=cycles+1;oldvs<=vs;if(!vs&&oldvs)frames<=frames+1;end
smart_terminal_overlay_parent #(.EXTERNAL_MAP_PIXELS(1),.EXTERNAL_SPECTRUM(1),.NUMBERED_SIX(1),.ENABLE_STARTUP_UI(0),.ENABLE_PERIOD_OSD(1),.SCREEN_W(1280),.SCREEN_H(720),.EVAC_PAGE1_HOLD_FRAMES(1),.EVAC_FADE_FRAMES(1),.ALARM_TO_EVAC_FRAMES(1)) original(.clk(clk),.rst(rst),.i_hs(hs),.i_vs(vs),.i_de(de),.i_rgb({x[7:0],y[7:0],x[7:0]^y[7:0]}),.emergency(frames>=2),.startup_loading(1'b0),.startup_progress(9'd350),.emergency_event(2'd1),.map_pixels_valid(frames>=3),.map_pixels_stale(1'b0),.map_live(1'b1),.map_scene(188'd0),.map_frame_tick(),.load_in_flight(cycles[15]),.load_nearly_done(1'b1),.fx_sel(retained_fx),.fx_off(1'b0),.audio_mag(cycles[15:0]),.audio_sample_valid(cycles%1563==0),.audio_sample(cycles[23:0]),.external_band_valid(cycles%97==0),.external_spectrum_live(1'b1),.external_band_data({cycles[7:4],cycles[15:0]}),.page_index(frames>=3?3'd1:frames>=2?3'd0:3'd2),.brightness(cycles[15:13]),.contrast(cycles[17:15]),.interval_selection(2'd1),.palette_bank(2'd0),.palette_write_enable(1'b0),.palette_write_address(10'd0),.palette_write_value(8'd0),.feature_mask(4'hf),.src_w(16'd640),.src_h(16'd480),.o_hs(a_hs),.o_vs(a_vs),.o_de(a_de),.o_rgb(a_rgb),.o_x(a_x),.o_y(a_y));
smart_terminal_overlay_pipelined #(.ENHANCED_AUDIO_VIS(1),.WAVE_W(384),.WAVE_H(160),.POINT_PX(2),.SAMPLE_STEP(3),.EXTERNAL_MAP_PIXELS(1),.EXTERNAL_SPECTRUM(1),.NUMBERED_SIX(1),.ENABLE_STARTUP_UI(0),.ENABLE_PERIOD_OSD(1),.SCREEN_W(1280),.SCREEN_H(720),.EVAC_PAGE1_HOLD_FRAMES(1),.EVAC_FADE_FRAMES(1),.ALARM_TO_EVAC_FRAMES(1)) optimized(.clk(clk),.rst(rst),.i_hs(hs),.i_vs(vs),.i_de(de),.i_rgb({x[7:0],y[7:0],x[7:0]^y[7:0]}),.emergency(frames>=2),.startup_loading(1'b0),.startup_progress(9'd350),.emergency_event(2'd1),.map_pixels_valid(frames>=3),.map_pixels_stale(1'b0),.map_live(1'b1),.map_scene(188'd0),.map_frame_tick(),.load_in_flight(cycles[15]),.load_nearly_done(1'b1),.fx_sel(retained_fx),.fx_off(1'b0),.audio_mag(cycles[15:0]),.audio_sample_valid(cycles%1563==0),.audio_sample(cycles[23:0]),.external_band_valid(cycles%97==0),.external_spectrum_live(1'b1),.external_band_data({cycles[7:4],cycles[15:0]}),.page_index(frames>=3?3'd1:frames>=2?3'd0:3'd2),.brightness(cycles[15:13]),.contrast(cycles[17:15]),.interval_selection(2'd1),.palette_bank(2'd0),.palette_write_enable(1'b0),.palette_write_address(10'd0),.palette_write_value(8'd0),.feature_mask(4'hf),.src_w(16'd640),.src_h(16'd480),.o_hs(b_hs),.o_vs(b_vs),.o_de(b_de),.o_rgb(b_rgb),.o_x(b_x),.o_y(b_y));
wire[50:0] expected={a_hs,a_vs,a_de,a_x,a_y,a_rgb};reg saw_map=0;integer checked=0;integer startup_pixels=0,normal_pixels=0,map_pixels=0;
always @(posedge clk)begin

 #1;
 if(!rst&&cycles>30)begin
 if($isunknown({b_hs,b_vs,b_de,b_x,b_y,b_rgb}))$fatal(1,"unknown overlay output");
 if(b_de&&optimized.evac_active)saw_map=1;
 if({b_hs,b_vs,b_de,b_x,b_y}!==expected[50:24])$fatal(1,"overlay changed after aligned +1 latency cycle=%d expected=%h got=%h",cycles,expected,{b_hs,b_vs,b_de,b_x,b_y,b_rgb});
 if({optimized.precise_audio.u_spectrum.xd,optimized.precise_audio.u_spectrum.yd}!=={optimized.s3_x,optimized.s3_y})$fatal(1,"Precise spectrum shifted");
 if({optimized.precise_audio.u_wave.x_d2,optimized.precise_audio.u_wave.y_d2}!=={optimized.s3_x,optimized.s3_y})$fatal(1,"Precise waveform shifted");
 if(b_de && !(b_x>=40&&b_x<424&&b_y>=130&&b_y<290) && !(b_x>=852&&b_x<1236&&b_y>=484&&b_y<644) && b_rgb!==expected[23:0])$fatal(1,"Non-audio picture/map/OSD pixel changed x%0d y%0d",b_x,b_y);
 checked=checked+1;if(b_de)begin if(frames<=1)startup_pixels=startup_pixels+1;else if(frames<3)normal_pixels=normal_pixels+1;else map_pixels=map_pixels+1;end
 end
end
initial begin repeat(10)@(negedge clk);rst=0;wait(frames==5);repeat(100)@(negedge clk);
 if(startup_pixels==0||normal_pixels==0||map_pixels==0||!saw_map)$fatal(1,"overlay coverage startup=%d normal=%d map=%d total=%d de=%b hs=%b",startup_pixels,normal_pixels,map_pixels,checked,b_de,b_hs);
 $display("PASS: Direct parent-map comparison preserves HS/VS/DE/XY and actual precise-panel alignment; no unknown output at %d checked cycles, startup=%d normal=%d map=%d active pixels; changing brightness/contrast, transitions, waveform/spectrum/OSD and emergency map",checked,startup_pixels,normal_pixels,map_pixels);$finish;end
initial begin #120000000;$fatal(1,"overlay timeout");end
endmodule
