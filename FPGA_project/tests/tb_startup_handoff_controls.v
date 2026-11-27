`timescale 1ns/1ps
module tb_startup_handoff_controls;
 reg clk=0,rst=1,vs=1,loading=1,load=1,nearly=1;
 always #5 clk=~clk;
 wire[23:0] rgb;wire de,hs,os;wire[11:0] x,y;
 smart_terminal_overlay_pipelined #(.ENABLE_STARTUP_UI(1),.USE_COLOUR_PALETTE(1),
 .EXTERNAL_MAP_PIXELS(1),.EXTERNAL_SPECTRUM(1),.REMOTE_MAP(1),.SCREEN_W(1280),.SCREEN_H(720)) dut(
 .clk(clk),.rst(rst),.i_hs(1'b0),.i_vs(vs),.i_de(1'b1),.i_rgb(24'hE0A060),
 .emergency(1'b0),.startup_loading(loading),.startup_progress(9'd0),.emergency_event(2'd0),
 // Ordinary fade/checker path is selector3; selector1 is now geometry flip.
 .load_in_flight(load),.load_nearly_done(nearly),.fx_sel(3'd3),.fx_off(1'b0),
 .audio_mag(16'd0),.audio_sample_valid(1'b0),.audio_sample(24'd0),
 .external_band_valid(1'b0),.external_spectrum_live(1'b0),.external_band_data(20'd0),
 .map_pixels_valid(1'b0),.map_pixels_stale(1'b0),.map_live(1'b0),.map_scene(188'd0),
 .map_frame_tick(),.page_index(3'd2),.brightness(3'd4),.contrast(3'd4),
 .interval_selection(2'd0),.playback_running(1'b1),.palette_bank(2'd0),
 .palette_write_enable(1'b0),.palette_write_address(10'd0),.palette_write_value(8'd0),
 .feature_mask(4'b0010),.src_w(16'd640),.src_h(16'd480),
 .o_hs(hs),.o_vs(os),.o_de(de),.o_x(x),.o_y(y),.o_rgb(rgb));
 task frame;begin vs=1;repeat(15)@(negedge clk);vs=0;repeat(35)@(negedge clk);end endtask
 task check;input condition;input[1023:0] msg;begin if(condition!==1'b1)$fatal(1,"%0s rgb=%h fade=%0d",msg,rgb,dut.fade_alpha);end endtask
 integer i,previous;
 initial begin
  force dut.x=900;force dut.y=300;
  repeat(8)@(negedge clk);rst=0;
  repeat(15)begin frame;check(rgb==24'h08182c&&dut.fade_alpha==0,"Waiting exposed source/fade");end
  loading=0;repeat(25)@(negedge clk);
  check(rgb==24'h08182c&&dut.startup_wait,"Readiness removed UI in the middle of a frame");
  repeat(5)begin frame;check(rgb==24'hE0A060&&dut.fade_alpha==0,"First photo dimmed by stale loading window");end
  load=0;nearly=0;frame;frame;
  check(!dut.startup_skip_fade,"Ordinary transitions failed to rearm");
  load=1;nearly=1;previous=0;
  repeat(8)begin frame;check(dut.fade_alpha>previous,"Ordinary fade-out no longer works");previous=dut.fade_alpha;end
  check(rgb==0&&dut.fade_alpha==255,"Ordinary fade endpoint missing");
  load=0;nearly=0;previous=255;
  repeat(10)begin frame;check(dut.fade_alpha<previous,"Ordinary fade-in no longer works");previous=dut.fade_alpha;end
  check(rgb==24'hE0A060,"Ordinary fade did not restore complete photo");
  loading=1;frame;check(rgb==24'h08182c,"Requalification lost persistent loading page");
  load=1;nearly=1;repeat(4)frame;loading=0;frame;
  check(rgb==24'hE0A060&&dut.fade_alpha==0,"Requalification inserted another black handoff");
  $display("PASS: mid-active readiness waits for VS; persistent loading and stale-nearly first-photo bypass; ordinary eight-frame fade-out/ten-frame fade-in rearmed with exact endpoints; repeat qualification has no black handoff");$finish;
 end
 initial begin #100000;$fatal(1,"Handoff controls timeout");end
endmodule
