`timescale 1ns/1ps
// Exercise the real palette/compositor/blend pipeline. Only vertical blanking
// is shortened; production 8/10-frame fades, 120-frame dwell and 51-frame map
// fade are unchanged. No production alpha/state register is forced.
module tb_transition_trim;
reg clk=0,rst=1,vs=1,emergency=0,load=0,nearly=0,off=0;
reg [2:0] page=2,fx=0;
reg [1:0] event_type=0;
reg map_valid=0,map_stale=0,particle_ready=0;
reg [23:0] input_rgb=24'hE0A060;
reg [11:0] probe_x=900,probe_y=300;
reg moving_probe=0,moving_input=0,compare_parent=0,compare_cut=0;
reg [31:0] random_word=32'h174625A9;
wire [7:0] particle_code={probe_x[7:3]^probe_y[7:3],(probe_x[2:0]|3'd1)};
wire [23:0] rgb,parent_rgb,cut_rgb;
wire hs_out,vs_out,de_out,parent_hs,parent_vs,parent_de,cut_hs,cut_vs,cut_de;
wire [11:0] x_out,y_out,parent_x,parent_y,cut_x,cut_y;
wire [12:0] particle_address,parent_particle_address,cut_particle_address;
localparam [23:0] BASE=24'hE0A060,NEW=24'h4060B0,MAP=24'h3080D0;
integer j,k,n,previous_alpha,intermediate,checks_parent=0,checks_cut=0;
integer checks_independent=0,retained_pixels=0,particle_hot_pixels=0;
integer cut_cases=0,retained_cases=0,emergency_cases=0;
always #5 clk=~clk;
always @(negedge clk)begin
 random_word={random_word[30:0],random_word[31]^random_word[21]^random_word[1]^random_word[0]};
 if(moving_probe)begin probe_x=random_word[10:0]%1280;probe_y=random_word[21:11]%720;end
 if(moving_input)input_rgb=random_word[23:0];
end
`define PARAMS .USE_COLOUR_PALETTE(1),.EXTERNAL_SPECTRUM(1),.REMOTE_MAP(1),.EXTERNAL_MAP_PIXELS(1),.ENABLE_PARTICLES(1),.ENABLE_PARTICLE_MOTION(1),.SCREEN_W(1280),.SCREEN_H(720)
`define COMMON .clk(clk),.rst(rst),.i_hs(1'b0),.i_vs(vs),.i_de(1'b1),.i_rgb(input_rgb),.emergency(emergency),.playback_running(1'b1),.startup_loading(1'b0),.startup_progress(9'd0),.map_pixels_valid(map_valid),.map_pixels_stale(map_stale),.emergency_event(event_type),.map_live(1'b0),.map_scene(188'd0),.map_frame_tick(),.load_in_flight(load),.load_nearly_done(nearly),.fx_sel(fx),.particle_motion(57'h12A68B351D42C3),.particle_ready(particle_ready),.particle_code(particle_code),.audio_mag(16'd0),.audio_sample_valid(1'b0),.audio_sample(24'd0),.external_band_valid(1'b0),.external_spectrum_live(1'b0),.external_band_data(20'd0),.page_index(page),.brightness(3'd4),.contrast(3'd4),.interval_selection(2'd0),.palette_bank(2'd0),.palette_write_enable(1'b0),.palette_write_address(10'd0),.palette_write_value(8'd0),.feature_mask(4'b0010),.src_w(16'd640),.src_h(16'd480)
smart_terminal_overlay_pipelined #(`PARAMS) dut(`COMMON,.fx_off(off),.particle_address(particle_address),.o_hs(hs_out),.o_vs(vs_out),.o_de(de_out),.o_rgb(rgb),.o_x(x_out),.o_y(y_out));
transition_trim_parent_overlay #(`PARAMS) parent(`COMMON,.fx_off(off),.particle_address(parent_particle_address),.o_hs(parent_hs),.o_vs(parent_vs),.o_de(parent_de),.o_rgb(parent_rgb),.o_x(parent_x),.o_y(parent_y));
transition_trim_parent_overlay #(`PARAMS) cut_parent(`COMMON,.fx_off(1'b1),.particle_address(cut_particle_address),.o_hs(cut_hs),.o_vs(cut_vs),.o_de(cut_de),.o_rgb(cut_rgb),.o_x(cut_x),.o_y(cut_y));
`undef COMMON
`undef PARAMS

// Check every clock, including changing input RGB, arbitrary in-raster pixel
// coordinates, synchronous switch/loading changes, and the output pipeline.
always @(posedge clk)begin
 #1;
 if(!rst && compare_parent)begin
  if({rgb,hs_out,vs_out,de_out,x_out,y_out,particle_address} !==
     {parent_rgb,parent_hs,parent_vs,parent_de,parent_x,parent_y,parent_particle_address})
   $fatal(1,"parent output mismatch fx=%0d off=%0d em=%0d x=%0d y=%0d rgb=%h parent=%h alpha=%0d parentalpha=%0d",fx,off,emergency,probe_x,probe_y,rgb,parent_rgb,dut.fade_alpha,parent.fade_alpha);
  if({dut.fade_alpha,dut.s1_fx_alpha,dut.particle_active,dut.evac_armed,dut.evac_fade,dut.page1_hold_cnt} !==
     {parent.fade_alpha,parent.s1_fx_alpha,parent.particle_active,parent.evac_armed,parent.evac_fade,parent.page1_hold_cnt})
   $fatal(1,"parent fade/state mismatch fx=%0d off=%0d em=%0d",fx,off,emergency);
  checks_parent=checks_parent+1;
  if(!emergency && dut.s1_fx_alpha>0 && dut.s1_fx_alpha<255)retained_pixels=retained_pixels+1;
  if(!emergency && dut.particle_hot)particle_hot_pixels=particle_hot_pixels+1;
 end
 if(!rst && compare_cut)begin
  if({rgb,hs_out,vs_out,de_out,x_out,y_out,particle_address} !==
     {cut_rgb,cut_hs,cut_vs,cut_de,cut_x,cut_y,cut_particle_address})
   $fatal(1,"hard-cut output differs from original disabled effect pipeline fx=%0d off=%0d ready=%0d rgb=%h expected=%h",fx,off,particle_ready,rgb,cut_rgb);
  if(dut.s1_fx_alpha!==0 || dut.fade_alpha!==0)
   $fatal(1,"disabled ordinary effect left alpha/fade fx=%0d off=%0d ready=%0d alpha=%0d fade=%0d",fx,off,particle_ready,dut.s1_fx_alpha,dut.fade_alpha);
  checks_cut=checks_cut+1;
 end
end

task check;
 input condition;input [1023:0] message;
 begin if(condition!==1'b1)$fatal(1,"FAIL: %0s fx=%0d off=%0d em=%0d ready=%0d fade=%0d mapfade=%0d",message,fx,off,emergency,particle_ready,dut.fade_alpha,dut.evac_fade);end
endtask
task frame;
 begin vs=1;repeat(12)@(negedge clk);vs=0;repeat(48)@(negedge clk);end
endtask
task restart;
 input [2:0] selection;input disable_fx;input ready;
 begin
  compare_parent=0;compare_cut=0;moving_probe=0;moving_input=0;
  rst=1;vs=1;emergency=0;load=0;nearly=0;page=2;
  map_valid=0;map_stale=0;input_rgb=BASE;probe_x=900;probe_y=300;
  fx=selection;off=disable_fx;particle_ready=ready;
  repeat(8)@(negedge clk);rst=0;repeat(24)@(negedge clk);frame;
 end
endtask
function [7:0] reference_channel;
 input [7:0] b,l,a;integer numerator;
 begin numerator=b*(255-a)+l*a;reference_channel=numerator/255;end
endfunction
function [23:0] reference_blend;
 input [23:0] b,l;input [7:0] a;
 begin reference_blend={reference_channel(b[23:16],l[23:16],a),reference_channel(b[15:8],l[15:8],a),reference_channel(b[7:0],l[7:0],a)};end
endfunction
task uniform_pixel;
 begin
  check(rgb===reference_blend(input_rgb,24'd0,dut.fade_alpha),"real compositor pixel differs from independent /255 fade arithmetic");
  check(dut.s1_fx_alpha===dut.fade_alpha,"ordinary selection changed emergency uniform alpha");
  checks_independent=checks_independent+1;
 end
endtask

task ordinary_cut;
 input [2:0] selection;input disable_fx;input ready;
 begin
  restart(selection,disable_fx,ready);compare_cut=1;
  check(rgb===BASE,"hard-cut ordinary base changed");
  load=1;repeat(6)begin frame;check(rgb===BASE,"slow prefetch darkened old complete picture");end
  nearly=1;repeat(12)begin frame;check(rgb===BASE,"removed effect darkened old picture during natural fade-out window");end
  input_rgb=NEW;page=3;load=0;nearly=0;
  repeat(24)@(negedge clk);check(rgb===NEW,"new complete picture was not exposed after the unchanged pipeline delay");
  repeat(14)begin frame;check(rgb===NEW,"removed effect introduced a fade-in");end
  // Vary source colors and pixels to compare the full actual output delay.
  moving_probe=1;moving_input=1;repeat(5)frame;
  compare_cut=0;cut_cases=cut_cases+1;
 end
endtask

task ordinary_retained;
 input [2:0] selection;
 begin
  restart(selection,0,selection==6);compare_parent=1;moving_probe=1;moving_input=1;
  load=1;repeat(6)frame;check(dut.fade_alpha==0,"retained effect darkened slow prefetch early");
  nearly=1;previous_alpha=0;intermediate=0;
  for(j=0;j<8;j=j+1)begin
   frame;check(dut.fade_alpha>previous_alpha,"retained natural fade-out stalled");
   if(dut.fade_alpha<255)intermediate=intermediate+1;previous_alpha=dut.fade_alpha;
  end
  check(dut.fade_alpha==255&&intermediate>=6,"retained mode lost 8-frame natural fade-out");
  page=3;load=0;nearly=0;previous_alpha=255;intermediate=0;
  for(j=0;j<(selection==6?43:10);j=j+1)begin
   frame;check(dut.fade_alpha<previous_alpha,"retained natural fade-in stalled");
   if(dut.fade_alpha>0)intermediate=intermediate+1;previous_alpha=dut.fade_alpha;
  end
  check(dut.fade_alpha==0&&intermediate>=8,"retained mode failed to finish original fade-in");
  repeat(3)frame;compare_parent=0;retained_cases=retained_cases+1;
 end
endtask

task emergency_uniform;
 input [2:0] selection;input disable_fx;
 begin
  restart(selection,disable_fx,0);compare_parent=1;
  emergency=1;page=0;repeat(4)frame;
  check(dut.emergency_entry_fast&&dut.fade_alpha==0,"05 first alarm no longer preempts immediately");uniform_pixel;
  repeat(25)begin frame;check(dut.fade_alpha==0&&rgb===BASE,"slow emergency prefetch darkened 05");end
  load=1;nearly=1;previous_alpha=0;intermediate=0;
  for(j=0;j<8;j=j+1)begin
   frame;check(dut.fade_alpha>previous_alpha,"05 to 06 fade-out stalled");uniform_pixel;
   if(dut.fade_alpha<255)intermediate=intermediate+1;previous_alpha=dut.fade_alpha;
  end
  check(dut.fade_alpha==255&&intermediate>=6,"05 did not fade to black");
  page=1;load=0;nearly=0;previous_alpha=255;intermediate=0;
  for(j=0;j<10;j=j+1)begin
   frame;check(dut.fade_alpha<previous_alpha,"06 fade-in stalled");uniform_pixel;
   if(dut.fade_alpha>0)intermediate=intermediate+1;previous_alpha=dut.fade_alpha;
  end
  check(dut.fade_alpha==0&&rgb===BASE&&intermediate>=8,"06 did not reach original brightness");
  repeat(110)frame;check(dut.fade_alpha==0&&rgb===BASE,"06 lost its complete visible dwell");
  load=1;nearly=1;previous_alpha=0;
  repeat(8)begin frame;check(dut.fade_alpha>previous_alpha,"06 to first map fade-out stalled");uniform_pixel;previous_alpha=dut.fade_alpha;end
  check(rgb==0,"06 was not completely black before first map commit");
  repeat(5)begin frame;check(rgb==0,"incomplete map was exposed during full-frame wait");end
  map_valid=1;input_rgb=MAP;load=0;nearly=0;previous_alpha=255;
  repeat(10)begin frame;check(dut.fade_alpha<previous_alpha,"first complete map fade-in stalled");uniform_pixel;previous_alpha=dut.fade_alpha;end
  check(rgb===MAP,"first complete external map lost full brightness");
  repeat(43)frame;check(dut.evac_fade==255,"original 51-frame map layer fade did not finish");
  emergency=0;page=2;map_valid=0;input_rgb=BASE;repeat(3)frame;
  check(dut.fade_alpha==0&&rgb===BASE,"normal return lost immediate complete picture");
  compare_parent=0;emergency_cases=emergency_cases+1;
 end
endtask

task emergency_particle_parent;
 begin
  restart(6,0,1);compare_parent=1;
  check(dut.particle_active,"ready particle mode not armed");
  emergency=1;page=0;repeat(4)frame;load=1;nearly=1;repeat(8)frame;
  check(dut.fade_alpha==255,"original particle-priority emergency fade-out failed");
  page=1;load=0;nearly=0;repeat(43)frame;
  check(dut.fade_alpha==0,"original particle-priority emergency fade-in failed");
  repeat(77)frame;load=1;nearly=1;repeat(8)frame;
  map_valid=1;input_rgb=MAP;load=0;nearly=0;repeat(55)frame;
  check(dut.fade_alpha==0&&dut.evac_fade==255,"ready particle emergency first map did not finish");
  emergency=0;page=2;map_valid=0;input_rgb=BASE;repeat(3)frame;
  compare_parent=0;
 end
endtask

initial begin
 force dut.x=probe_x;force dut.y=probe_y;
 force parent.x=probe_x;force parent.y=probe_y;
 force cut_parent.x=probe_x;force cut_parent.y=probe_y;
 ordinary_cut(0,0,0);ordinary_cut(4,0,0);ordinary_cut(5,0,0);ordinary_cut(7,0,0);
 ordinary_cut(6,0,0);
 for(k=0;k<8;k=k+1)ordinary_cut(k,1,1);
 // A very slow ordinary source still stays visible past the old backstop.
 restart(4,0,0);compare_cut=1;load=1;nearly=0;repeat(245)frame;
 check(rgb===BASE&&dut.fade_alpha==0,"removed effect resurfaced at timeout/backstop");compare_cut=0;
 $display("PASS: %0d ordinary hard-cut cases (removed 0/4/5/7, particle 6 not ready, all eight off-switch codes), natural load/nearly/commit and 8/10-frame windows; %0d clock-exact comparisons to original disabled output pipeline; slow-source backstop stays visible",cut_cases,checks_cut);
 ordinary_retained(1);ordinary_retained(2);ordinary_retained(3);ordinary_retained(6);
 check(retained_pixels>1000&&particle_hot_pixels>10,"retained pattern/particle coverage was insufficient");
 $display("PASS: %0d retained ordinary modes 1/2/3/6-ready are bit/cycle identical to captured parent compositor and original transition_fx; %0d intermediate-alpha pixels, %0d hot particle pixels",retained_cases,retained_pixels,particle_hot_pixels);
 for(n=0;n<16;n=n+1)emergency_uniform(n[2:0],n[3]);
 $display("PASS: all %0d ordinary switch combinations preserve original 05 -> 06 -> first complete external map fades, 120-frame dwell, slow prefetch/full-frame wait, immediate entry/exit and 51-frame map-layer completion; particle not ready; %0d independent /255 pixel checks",emergency_cases,checks_independent);
 emergency_particle_parent;
 $display("PASS: original ready-particle priority during emergency is preserved against parent, including first external map; total %0d clock-exact parent output/state comparisons",checks_parent);
 $finish;
end
initial begin #10000000;$fatal(1,"FAIL: transition trim timeout");end
endmodule
