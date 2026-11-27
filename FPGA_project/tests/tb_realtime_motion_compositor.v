`timescale 1ns/1ps
module tb_realtime_motion_compositor;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [11:0] h=0,v=0;integer frames=0;
 wire de=h<1280&&v<720,vs=v==722;
 always @(posedge clk)if(rst)begin h<=0;v<=0;frames<=0;end
 else if(h==1295)begin h<=0;if(v==723)begin v<=0;frames<=frames+1;end else v<=v+1'b1;end else h<=h+1'b1;
 reg [7:0] atlas[0:8191],code;wire [12:0] address;
 always @(posedge clk)code<=atlas[address];
 wire [23:0] rgb;wire oh,ov,od;wire [11:0] ox,oy;
 wire [7:0] phase=frames<2?0:frames==2?64:frames==3?128:frames==4?192:frames==5?255:frames==6?0:128;
 wire off=frames==7;wire [2:0] fx=frames==8?(h[7:5]<6?h[7:5]:3'd5):3'd6;wire atlas_ready=frames<9;
 smart_terminal_overlay_pipelined #(.ENABLE_PARTICLES(1),.ENABLE_PARTICLE_MOTION(1),.USE_COLOUR_PALETTE(1),.EXTERNAL_SPECTRUM(1),.REMOTE_MAP(1),.EXTERNAL_MAP_PIXELS(1),.SCREEN_W(1280),.SCREEN_H(720)) dut(
 .clk(clk),.rst(rst),.i_hs(1'b0),.i_vs(vs),.i_de(de),.i_rgb(24'h906030),.emergency(1'b0),
 .playback_running(1'b1),.startup_loading(1'b0),.startup_progress(9'd0),.map_pixels_valid(1'b0),.map_pixels_stale(1'b0),.emergency_event(2'd0),
 .map_live(1'b0),.map_scene(188'd0),.map_frame_tick(),.load_in_flight(1'b0),.load_nearly_done(1'b0),.fx_sel(fx),.fx_off(off),
 .particle_motion(57'h123456789abcd),.particle_ready(atlas_ready),.particle_code(code),.particle_address(address),
 .audio_mag(16'd0),.audio_sample_valid(1'b0),.audio_sample(24'd0),.external_band_valid(1'b0),.external_spectrum_live(1'b0),.external_band_data(20'd0),
 .page_index(3'd2),.brightness(3'd4),.contrast(3'd4),.interval_selection(2'd0),.palette_bank(2'd0),.palette_write_enable(1'b0),.palette_write_address(10'd0),.palette_write_value(8'd0),
 .feature_mask(4'b0010),.src_w(16'd640),.src_h(16'd480),.o_hs(oh),.o_vs(ov),.o_de(od),.o_rgb(rgb),.o_x(ox),.o_y(oy));
 function [7:0] blend;input [7:0] base,layer,alpha;integer n;begin n=base*(255-alpha)+layer*alpha;blend=n/255;end endfunction
 reg [23:0] expected[0:7];reg [2:0] expected_flags[0:7];
 integer i,idx,code_ref,glow,local_phase,wide,alpha,age,distance,layer_g,layer_b,dx,dy,fade;
 reg active;reg [23:0] result;integer checked=0,blue_pixels=0,black_pixels=0,original_pixels=0;
 always @(posedge clk)begin
  if(!rst && frames>0)begin
   begin
    integer row,off,xx,yy;row=(dut.y>>7)&7;off=(dut.motion_frame>>(9+row*6))&63;
    xx=((dut.x>>3)+(dut.x>=640?-off:off))&127;yy=((dut.y>>3)+((dut.motion_frame>>3)&63))&63;
    idx=yy*128+xx;
   end
   code_ref=atlas[idx];
   if(code!==atlas[idx])$fatal(1,"atlas prefetch not aligned at x=%d y=%d got=%h ref=%h",dut.x,dut.y,code,atlas[idx]);
   active=dut.particle_armed&&dut.fx_sync1==6&&!dut.fxo_sync1;
   dx=dut.x>640?dut.x-640:640-dut.x;dy=dut.y>360?dut.y-360:360-dut.y;
   case(dut.fx_sync1)
    1:local_phase=(dut.y&7)*16;
    2:local_phase=(dut.x&7)*16;
    3:local_phase=(((dut.x>>6)&1)^((dut.y>>6)&1))?128:0;
    4:local_phase=(dut.x>>4)+(dut.y>>4);
    5:local_phase=(dx+dy)>>3;
    default:local_phase=0;
   endcase
   if(active)local_phase=(code_ref>>3)*4;if(local_phase>128)local_phase=128;
   fade=dut.fade_alpha;wide=fade+((active||(dut.fx_sync1>=1&&dut.fx_sync1<=5))?fade/2:0);alpha=wide-local_phase;
   if(alpha<0)alpha=0;if(alpha>255)alpha=255;if(dut.fxo_sync1)alpha=0;
   glow=code_ref&7;age=fade>>3;distance=age-(code_ref>>3);if(distance<0)distance=-distance;
   layer_g=0;layer_b=0;
   if(active && fade!=0 && fade!=255 && distance<4 && glow!=0)begin layer_g=glow*16+15;layer_b=glow*32+31;end
   result={blend(8'h90,0,alpha[7:0]),blend(8'h60,layer_g[7:0],alpha[7:0]),blend(8'h30,layer_b[7:0],alpha[7:0])};
   expected[0]<=result;expected_flags[0]<={1'b0,vs,de};
   for(i=1;i<8;i=i+1)begin expected[i]<=expected[i-1];expected_flags[i]<=expected_flags[i-1];end
   #1;
   if(frames>1 && od && oy>=80)begin
    if(rgb!==expected[7])$fatal(1,"particle compositor pixel mismatch frame=%d x=%d y=%d got=%h ref=%h",frames,ox,oy,rgb,expected[7]);
    if({oh,ov,od}!==expected_flags[7])$fatal(1,"particle sync phase changed");
    checked=checked+1;if(rgb[7:0]>rgb[23:16])blue_pixels=blue_pixels+1;
    if(rgb==0)black_pixels=black_pixels+1;if(rgb==24'h906030)original_pixels=original_pixels+1;
   end
  end
 end
 initial begin
  $readmemh("particle_reference.hex",atlas);force dut.fade_alpha=phase;
  repeat(12)@(negedge clk);rst=0;
  wait(frames==9);wait(v==721); // Arm fallback at a zero-alpha frame boundary.
  force dut.fade_alpha=8'd0;wait(frames==10);repeat(10)@(negedge clk);release dut.fade_alpha;force dut.fade_alpha=phase;
  wait(frames==11);repeat(30)@(negedge clk);
  if(checked<500000 || blue_pixels==0 || black_pixels==0 || original_pixels==0)$fatal(1,"particle RGB coverage missing");
  $display("PASS: %0d independent compositor RGB and sync pixels, aligned atlas lookahead, blue glow, fade endpoints, off switch, all six legacy effects and not-ready uniform fallback",checked);$finish;
 end
 initial begin #120000000;$fatal(1,"particle compositor timeout");end
endmodule
