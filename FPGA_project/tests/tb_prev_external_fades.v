`timescale 1ns/1ps
// Exercise the production compositor, including pixel blend arithmetic.
// Only the blanking interval is shortened; the 120-frame static hold and
// default 51-frame map fade are kept at their actual production settings.
module tb_prev_external_fades;
reg clk=0,rst=1,vs=1,emergency=0,load=0,nearly=0,off=1;
reg [2:0] page=2,fx=0;
reg [1:0] event_type=0;
wire [23:0] rgb;reg map_valid=0,map_stale=0;reg [23:0] input_rgb=24'hE0A060;
wire hs_out,vs_out,de_out;
wire [11:0] x_out,y_out;
localparam [23:0] BASE=24'hE0A060;
integer j,k,previous_alpha,intermediate,wait_frames,checked_pixels=0;
reg [23:0] expected_registered_pixel;
always #5 clk=~clk;
smart_terminal_overlay_pipelined #(
 .USE_COLOUR_PALETTE(1),.EXTERNAL_SPECTRUM(1),.REMOTE_MAP(1),.EXTERNAL_MAP_PIXELS(1),
 .SCREEN_W(1280),.SCREEN_H(720)
) dut(
 .clk(clk),.rst(rst),.i_hs(1'b0),.i_vs(vs),.i_de(1'b1),.i_rgb(input_rgb),
 .emergency(emergency),.playback_running(1'b1),.startup_loading(1'b0),.startup_progress(9'd0),.map_pixels_valid(map_valid),.map_pixels_stale(map_stale),.emergency_event(event_type),
 .map_live(1'b0),.map_scene(188'd0),.map_frame_tick(),
 .load_in_flight(load),.load_nearly_done(nearly),.fx_sel(fx),.fx_off(off),
 .audio_mag(16'd0),.audio_sample_valid(1'b0),.audio_sample(24'd0),
 .external_band_valid(1'b0),.external_spectrum_live(1'b0),.external_band_data(20'd0),
 .page_index(page),.brightness(3'd4),.contrast(3'd4),.interval_selection(2'd0),
 .palette_bank(2'd0),.palette_write_enable(1'b0),.palette_write_address(10'd0),.palette_write_value(8'd0),
 .feature_mask(4'b0010),.src_w(16'd640),.src_h(16'd480),
 .o_hs(hs_out),.o_vs(vs_out),.o_de(de_out),.o_rgb(rgb),.o_x(x_out),.o_y(y_out));

task check;
 input condition;input [1023:0] message;
 begin if(condition!==1'b1)$fatal(1,"FAIL: %0s page=%0d fx=%0d fade=%0d map=%0d",message,page,fx,dut.fade_alpha,dut.evac_fade);end
endtask
task frame;
 begin vs=1;repeat(12)@(negedge clk);vs=0;repeat(30)@(negedge clk);end
endtask
function [7:0] reference_channel;
 input [7:0] b,l,a;
 integer numerator;
 begin numerator=b*(255-a)+l*a;reference_channel=numerator/255;end
endfunction
function [23:0] reference_blend;
 input [23:0] b,l;input [7:0] a;
 begin reference_blend={reference_channel(b[23:16],l[23:16],a),
                       reference_channel(b[15:8],l[15:8],a),
                       reference_channel(b[7:0],l[7:0],a)};end
endfunction
// The final register consumes the previous s6 pixel; compare every actual
// sample with independent /255 arithmetic, including a moving map.
task check_static_pixel;
 begin
  check(!dut.evac_active,"map covered a static picture before its complete hold");
  check(rgb===reference_blend(BASE,24'd0,dut.fade_alpha),"static fade pixel differs from independent /255 reference");
 end
endtask
task clear_mode;
 begin emergency=0;page=2;load=0;nearly=0;frame;frame;
  check(!dut.evac_armed&&dut.evac_fade==0&&dut.s6_evac_alpha==0,"exit left map/fade state");
  check(rgb===BASE,"normal picture not restored promptly");
 end
endtask

initial begin
 // Probe a real 720p interior pixel outside all text/audio-panel regions.
 force dut.x=12'd900;force dut.y=12'd300;
 repeat(8)@(negedge clk);rst=0;repeat(24)@(negedge clk);
 check(rgb===BASE,"ordinary output changed with ordinary effects disabled");
 // Exercise every stored ordinary switch selection, including fx_off=1.
 for(k=0;k<8;k=k+1)begin
  fx=k;off=k[0];emergency=1;page=0;load=0;nearly=0;
  repeat(4)frame;
  check(dut.emergency_entry_fast&&dut.fade_alpha==0,"first alarm preemption gained an unwanted black wait");
  check_static_pixel;
  // A not-yet-ready prefetch is visually silent, even if it takes extra frames.
  repeat(25)frame;
  check(dut.fade_alpha==0&&rgb===BASE,"slow source darkened the alarm before next frame was ready");
  load=1;nearly=1;previous_alpha=0;intermediate=0;
  for(j=0;j<8;j=j+1)begin
   frame;
   check(dut.fade_alpha>previous_alpha,"alarm fade did not advance monotonically");
   if(dut.fade_alpha<255)intermediate=intermediate+1;
   check_static_pixel;
   check(dut.s1_fx_alpha==dut.fade_alpha,"emergency fade was patterned or disabled by ordinary switches");
   previous_alpha=dut.fade_alpha;
  end
  check(dut.fade_alpha==255&&intermediate>=6,"alarm did not fade to a complete black endpoint");
  page=1;load=0;nearly=0;previous_alpha=255;intermediate=0;
  for(j=0;j<10;j=j+1)begin
   frame;
   check(dut.fade_alpha<previous_alpha,"evacuation picture fade-in did not progress");
   if(dut.fade_alpha>0)intermediate=intermediate+1;
   check_static_pixel;previous_alpha=dut.fade_alpha;
  end
  check(dut.fade_alpha==0&&rgb===BASE&&intermediate>=8,"second picture did not complete its soft fade-in");
  clear_mode;
 end
 $display("PASS: alarm -> static evacuation uses intermediate per-pixel fade values with all eight ordinary effect selections and either off-switch state; slow prefetch remains visible; first alarm and exit stay immediate");


 emergency=1;page=0;repeat(4)frame;
 page=1;repeat(120)frame;
 check(dut.fade_alpha==0 && rgb===BASE,"06 did not retain its visible dwell");
 load=1;nearly=1;previous_alpha=0;
 repeat(8)begin frame;check(dut.fade_alpha>previous_alpha,"06 fade-out stalled");previous_alpha=dut.fade_alpha;end
 check(rgb==0,"06 did not fade completely before map swap");
 repeat(5)frame;check(rgb==0,"waiting for complete B map exposed incomplete pixels");
 map_valid=1;input_rgb=24'h3080D0;load=0;nearly=0;previous_alpha=255;
 repeat(10)begin
  frame;check(dut.fade_alpha<previous_alpha,"received map fade-in stalled");previous_alpha=dut.fade_alpha;
  check(rgb===reference_blend(input_rgb,24'd0,dut.fade_alpha),"external B map bypassed or doubled its fade");
 end
 check(rgb===24'h3080D0,"B map did not reach full brightness");
 map_stale=1;force dut.x=12'd32;force dut.y=12'd710;
 repeat(30)@(negedge clk);check(rgb===24'hB34D31,"stale received map lost its offline indicator");
 map_stale=0;repeat(30)@(negedge clk);check(rgb===input_rgb,"online map retained stale marker");
 force dut.x=12'd900;force dut.y=12'd300;
 map_valid=0;input_rgb=BASE;clear_mode;
 $display("PASS: actual external B map pixels fade out from complete 06, wait for full map, then fade in monotonically through compositor; no self-blend bypass; normal restored");$finish;
end
initial begin #3000000;$fatal(1,"FAIL: external fade timeout");end
endmodule
