`timescale 1ns/1ps
module tb_resource_particle_exact;
 reg clk=0;always #5 clk=~clk;
 reg [9:0] x=0;reg [8:0] y=0,phase=0;wire [15:0] n0,n1,p0,p1;integer i,cycles=0;
 b_particle_shader d0(.clk(clk),.x(x),.y(y),.phase(phase),.rgb(n0));
 b_particle_shader #(.NATIVE_VGA(1)) d1(.clk(clk),.x(x),.y(y),.phase(phase),.rgb(n1));
 ref_resource_b_particle_shader r0(.clk(clk),.x(x),.y(y),.phase(phase),.rgb(p0));
 ref_resource_b_particle_shader #(.NATIVE_VGA(1)) r1(.clk(clk),.x(x),.y(y),.phase(phase),.rgb(p1));
 always @(posedge clk)begin cycles=cycles+1;#1;if(cycles>8 && (n0!==p0 || n1!==p1))$fatal(1,"particle latency/value mismatch cycle=%0d x=%0d y=%0d phase=%0d",cycles,x,y,phase);end
 initial begin
  #1;for(i=0;i<65536;i=i+1)if(d0.geometry_dictionary[{d0.geometry_index[i>>6],i[5:0]}]!==r0.geometry[i])$fatal(1,"lossless geometry mismatch address=%0d",i);
  for(i=0;i<2097152;i=i+1)begin @(negedge clk);x=i[9:0];y=i[18:10];phase=(i*17)^(i>>7)^(i>>17);end
  repeat(10)@(negedge clk);
  $display("PASS:65536 frozen geometry addresses reconstructed exactly;2097152 consecutive full-port x/y/phase samples in both native and legacy shader modes match RGB cycle-for-cycle, unchanged five-cycle contract");$finish;
 end
 initial begin #30000000;$fatal(1,"particle exact timeout");end
endmodule

module resource_text_pair #(parameter W=1280,FAST=1)(input clk,rst,emergency,loading,play,input [8:0] progress,input [11:0] x,y,xpre,ypre,input [2:0] page,bright,contrast,input [1:0] interval,input [71:0] resolution);
 wire [23:0] new_rgb,old_rgb;wire [7:0] new_alpha,old_alpha;
 text_overlay_8x8 #(.SCREEN_W(W),.SCREEN_H(720),.USE_BANNER_ROM(1),.ENABLE_PERIOD_OSD(1),.DEMO_FAST_PERIODS(FAST),.ENABLE_PLAYBACK_OSD(1),.ENABLE_STARTUP_UI(1),.CLK_FREQ_HZ(1000)) d(
 .clk(clk),.rst(rst),.emergency(emergency),.startup_loading(loading),.startup_progress(progress),.blink_on(progress[4]),.x(x),.y(y),.x_pre(xpre),.y_pre(ypre),.page_index(page),.brightness(bright),.contrast(contrast),.interval_selection(interval),.playback_running(play),.elapsed_seconds(progress[6:0]),.scroll_phase(xpre),.scroll_phase_pre(xpre),.feature_mask(4'hf),.res_str(resolution),.text_rgb(new_rgb),.text_alpha(new_alpha));
 ref_resource_text_overlay_8x8 #(.SCREEN_W(W),.SCREEN_H(720),.USE_BANNER_ROM(1),.ENABLE_PERIOD_OSD(1),.DEMO_FAST_PERIODS(FAST),.ENABLE_PLAYBACK_OSD(1),.ENABLE_STARTUP_UI(1),.CLK_FREQ_HZ(1000)) p(
 .clk(clk),.rst(rst),.emergency(emergency),.startup_loading(loading),.startup_progress(progress),.blink_on(progress[4]),.x(x),.y(y),.x_pre(xpre),.y_pre(ypre),.page_index(page),.brightness(bright),.contrast(contrast),.interval_selection(interval),.playback_running(play),.elapsed_seconds(progress[6:0]),.scroll_phase(xpre),.scroll_phase_pre(xpre),.feature_mask(4'hf),.res_str(resolution),.text_rgb(old_rgb),.text_alpha(old_alpha));
 always @(posedge clk)begin #1;if(!rst && (new_rgb!==old_rgb || new_alpha!==old_alpha))$fatal(1,"text mismatch W=%0d FAST=%0d x=%0d y=%0d rgb=%h/%h a=%h/%h",W,FAST,x,y,new_rgb,old_rgb,new_alpha,old_alpha);end
endmodule

module tb_resource_text_exact;
 reg clk=0,rst=1,emergency=0,loading=0,play=1;always #5 clk=~clk;
 reg [8:0] progress=0;reg [11:0] x=0,y=0,xpre=0,ypre=0;
 reg [2:0] page=2,bright=4,contrast=4;reg [1:0] interval=0;reg [71:0] resolution=" 640X 480";
 resource_text_pair a(.*);
 resource_text_pair #(.W(640),.FAST(0)) b(.*);
 resource_text_pair #(.W(1279)) c(.*);
 integer ch,row,col,xx,yy,f,i;reg actual,expected;
 initial begin
  #1;for(ch=0;ch<256;ch=ch+1)for(row=0;row<8;row=row+1)for(col=0;col<8;col=col+1)begin
   expected=a.p.status_font_memory[ch*64+row*8+col];
   actual=a.d.status_font_memory[ch*64+row*8+col];
   if(actual!==expected)$fatal(1,"font compression changed ch=%0d row=%0d col=%0d",ch,row,col);
  end
  repeat(12)@(negedge clk);rst=0;
  for(f=0;f<4;f=f+1)for(yy=0;yy<720;yy=yy+1)for(xx=0;xx<1280;xx=xx+1)begin
   @(negedge clk);xpre=xx;ypre=yy;x=xx==0?1279:xx-1;y=xx==0?yy-1:yy;
   if(xx%32==0)begin page=(xx+yy)&7;bright=yy&7;contrast=(yy>>3)&7;interval=(xx>>5)&3;progress=yy;play=yy[3];loading=(f==0);emergency=(f==3);
    resolution={8'(xx^yy),8'(xx+yy),8'(xx-yy),8'(yy),8'h58,8'(yy*3),8'(yy*7),8'(xx*13),8'(xx*17)};
   end
  end
  for(i=0;i<65536;i=i+1)begin @(negedge clk);xpre=(i*17)^(i>>7);ypre=(i*31)^(i>>3);x=xpre-1;y=ypre;loading=i[8];emergency=i[9];end
  repeat(4)@(negedge clk);
  $display("PASS:all16384 frozen font bits preserved;four complete720p rasters plus65536 full12-bit coordinate samples with unconstrained ASCII metadata, loading/normal/emergency, all interval/play modes; aligned1280/640 and unaligned1279 text RGB/alpha cycle-exact");$finish;
 end
 initial begin #50000000;$fatal(1,"text exact timeout");end
endmodule

module tb_resource_audio_exact;
 reg clk=0,rst=1,frame_tick=0,band_valid=0,source_live=1,audio_valid=0;always #5 clk=~clk;
 reg [4:0] band_idx=0;reg [15:0] band_mag=0;reg [23:0] sample=0;reg [11:0] x=0,y=0;
 wire [23:0] sn,sp,wn,wp;wire [7:0] san,sap,wan,wap;integer i,checks=0;
 audio_spectrum_precise_overlay a(.clk(clk),.rst(rst),.frame_tick(frame_tick),.band_valid(band_valid),.band_idx(band_idx),.band_mag(band_mag),.source_live(source_live),.x(x),.y(y),.bars_rgb(sn),.bars_alpha(san));
 ref_resource_audio_spectrum_precise_overlay b(.clk(clk),.rst(rst),.frame_tick(frame_tick),.band_valid(band_valid),.band_idx(band_idx),.band_mag(band_mag),.source_live(source_live),.x(x),.y(y),.bars_rgb(sp),.bars_alpha(sap));
 audio_waveform_precise_overlay #(.WAVE_W(384),.WAVE_H(160),.WAVE_X(40),.WAVE_Y(484),.POINT_PX(2),.SAMPLE_STEP(3)) c(.clk(clk),.rst(rst),.frame_tick(frame_tick),.audio_sample_valid(audio_valid),.audio_sample(sample),.x(x),.y(y),.wave_rgb(wn),.wave_alpha(wan));
 ref_resource_audio_waveform_precise_overlay #(.WAVE_W(384),.WAVE_H(160),.WAVE_X(40),.WAVE_Y(484),.POINT_PX(2),.SAMPLE_STEP(3)) d(.clk(clk),.rst(rst),.frame_tick(frame_tick),.audio_sample_valid(audio_valid),.audio_sample(sample),.x(x),.y(y),.wave_rgb(wp),.wave_alpha(wap));
 always @(posedge clk)begin #1;if(!rst)begin
  if(sn!==sp || san!==sap || wn!==wp || wan!==wap)$fatal(1,"audio pixels/latency changed x=%0d y=%0d spectrum=%h/%h wave=%h/%h",x,y,sn,sp,wn,wp);
  if(a.fp!==b.fp || a.lp!==b.lp || c.glyph!==d.glyph)$fatal(1,"folded font lookup changed");checks=checks+1;
 end end
 initial begin
  repeat(12)@(negedge clk);rst=0;
  for(i=0;i<2097152;i=i+1)begin @(negedge clk);
   x=i[11:0];y=i[20:12];frame_tick=i%4096==0;band_valid=i%23==0;band_idx=(i/23)%32;band_mag=i*97;
   source_live=i[17:16]!=3;audio_valid=i%3==0;sample=(i*65537)^(i>>6);
  end
  repeat(5)@(negedge clk);
  $display("PASS:2097152 consecutive full-range spectrum/wave samples, exact frozen RGB/alpha and combinational glyphs, live/offline, complete/incomplete band windows, peak decay and PCM capture; unchanged pixel latency");$finish;
 end
 initial begin #25000000;$fatal(1,"audio exact timeout");end
endmodule
