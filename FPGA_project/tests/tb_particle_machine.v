`timescale 1ns/1ps
module tb_particle_machine;
reg clk=0,rst=1,vs=1,emergency=0,load=0,nearly=0,off=0,ready=1,map_valid=0;
reg [23:0] background=24'h906030;
reg [2:0] page=2;wire [23:0] rgb;integer i,previous,blue_count=0;
always #5 clk=~clk;
smart_terminal_overlay_pipelined #(.ENABLE_PARTICLES(1),.USE_COLOUR_PALETTE(1),.EXTERNAL_SPECTRUM(1),.REMOTE_MAP(1),.EXTERNAL_MAP_PIXELS(1),.SCREEN_W(1280),.SCREEN_H(720)) dut(
 .clk(clk),.rst(rst),.i_hs(1'b0),.i_vs(vs),.i_de(1'b1),.i_rgb(background),
 .emergency(emergency),.playback_running(1'b1),.startup_loading(1'b0),.startup_progress(9'd0),.map_pixels_valid(map_valid),.map_pixels_stale(1'b0),.emergency_event(2'd0),
 .map_live(1'b0),.map_scene(188'd0),.map_frame_tick(),.load_in_flight(load),.load_nearly_done(nearly),.fx_sel(3'd6),.fx_off(off),
 .particle_ready(ready),.particle_code(8'h87),.particle_address(),
 .audio_mag(16'd0),.audio_sample_valid(1'b0),.audio_sample(24'd0),.external_band_valid(1'b0),.external_spectrum_live(1'b0),.external_band_data(20'd0),
 .page_index(page),.brightness(3'd4),.contrast(3'd4),.interval_selection(2'd0),.palette_bank(2'd0),.palette_write_enable(1'b0),.palette_write_address(10'd0),.palette_write_value(8'd0),
 .feature_mask(4'b0010),.src_w(16'd640),.src_h(16'd480),.o_hs(),.o_vs(),.o_de(),.o_rgb(rgb),.o_x(),.o_y());
task frame;begin vs=1;repeat(12)@(negedge clk);vs=0;repeat(30)@(negedge clk);end endtask
task check;input good;input [511:0] message;begin if(good!==1'b1)$fatal(1,"%0s fade=%d rgb=%h",message,dut.fade_alpha,rgb);end endtask
task transition;
 input particle_expected;integer steps;
 begin
  load=1;nearly=1;previous=0;
  repeat(8)begin frame;check(dut.fade_alpha>previous,"fade-out stalled");previous=dut.fade_alpha;end
  check(rgb==0,"buffer switch endpoint not completely black");
  page=page==2?3:2;load=0;nearly=0;steps=0;previous=255;
  while(dut.fade_alpha!=0)begin
   frame;check(dut.fade_alpha<previous,"fade-in stalled");previous=dut.fade_alpha;steps=steps+1;
   if(rgb[7:0]>rgb[23:16])blue_count=blue_count+1;
  end
  check(steps==(particle_expected?43:10),"unexpected fade-in duration");
  check(rgb==24'h906030,"new picture not restored exactly");
 end endtask
initial begin
 force dut.x=12'd900;force dut.y=12'd300;
 repeat(12)@(negedge clk);rst=0;repeat(3)frame;
 check(dut.particle_active,"valid atlas did not arm");transition(1);
 ready=0;repeat(3)frame;check(!dut.particle_active,"not-ready failed to select fallback");transition(0);
 ready=1;repeat(3)frame;off=1;repeat(3)frame;check(!dut.particle_active,"off switch did not bypass particles");
 off=0;emergency=1;page=0;repeat(5)frame;check(dut.fade_alpha==0,"first emergency acquired a black wait");
 load=1;nearly=1;repeat(8)frame;check(rgb==0,"emergency 05 endpoint incomplete");
 page=1;load=0;nearly=0;repeat(43)frame;check(rgb==24'h906030,"06 particle fade-in incomplete");
 repeat(120)frame;load=1;nearly=1;repeat(8)frame;check(rgb==0,"06 endpoint before map not black");
 repeat(5)frame;check(rgb==0,"waiting for complete map exposed stale pixels");
 map_valid=1;background=24'h305080;load=0;nearly=0;repeat(43)frame;
 check(rgb==24'h305080,"received B map did not complete particle fade-in");
 emergency=0;page=2;map_valid=0;background=24'h906030;repeat(4)frame;check(rgb==24'h906030,"emergency exit not immediate");
 check(blue_count>0,"no visible blue glow during transition");
 $display("PASS: real transition state machine: 8-frame fade-out/43-frame particle fade-in, visible blue glow, exact switch endpoints, 10-frame uniform fallback, off switch, emergency 05/06, wait for complete B map, particle map fade-in and immediate exit");$finish;
end
initial begin #1000000;$fatal(1,"particle state timeout");end
endmodule
