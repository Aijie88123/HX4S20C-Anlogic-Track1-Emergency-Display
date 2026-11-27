// Twelve full-rate DFT results. Small RAMs are deliberately not reset:
// validity gates hide them until a complete window is committed in vblank.
// One shared update engine replaces sixteen parallel envelope arithmetic paths.
module audio_spectrum_precise_overlay #(
 parameter SCREEN_W=1280,SCREEN_H=720,BAR_W=384,BAR_H=160,
 parameter BAR_X=852,BAR_Y=484,N_BANDS=12,HEIGHT_SCALE_13_8=1,PITCH_DETAIL=1,EXTERNAL_SOURCE=1,LOG_POWER=1)(
 input clk,rst,frame_tick,band_valid,input [4:0] band_idx,input [15:0] band_mag,input source_live,
 input [11:0] x,y,output reg [23:0] bars_rgb,output reg [7:0] bars_alpha);
 reg [7:0] windows[0:31];reg [7:0] levels[0:15],peaks[0:15];reg [2:0] ages[0:15];
 reg collect_bank,latest_bank,snapshot_bank,have_window,display_valid,updating;
 reg [15:0] mask,maximum;reg [3:0] maximum_index,latest_index,display_index,update_index,snapshot_index;
 reg latest_valid,display_peak_valid,snapshot_peak_valid;
 reg update_phase;
 reg [7:0] target_r,old_level_r,old_peak_r;reg [2:0] old_age_r;
 reg [2:0] idle_frames;
 wire [11:0] code=band_mag[15:4];
 wire [11:0] relative_power=code>672?code-12'd672:12'd0;
 wire [13:0] expanded_power={2'd0,relative_power}+({2'd0,relative_power}<<1);
 wire [11:0] height_uncapped=expanded_power>>5;
 wire [7:0] incoming_height=height_uncapped>BAR_H-28?BAR_H-28:height_uncapped[7:0];
 wire incoming=band_valid&&band_idx<12;
 wire wins=band_idx==0||band_mag>maximum;
 wire complete=incoming&&((band_idx==0?16'h0001:mask|(16'h0001<<band_idx))==16'h0fff);
 wire [7:0] target=have_window&&idle_frames<5?windows[{snapshot_bank,update_index}]:8'd0;
 wire [7:0] old_level=display_valid?levels[update_index]:8'd0;
 wire [7:0] old_peak=display_valid?peaks[update_index]:8'd0;
 wire [2:0] old_age=display_valid?ages[update_index]:3'd0;
 always @(posedge clk)begin
  if(incoming)windows[{collect_bank,band_idx[3:0]}]<=incoming_height;
  if(updating&&!update_phase)begin
   target_r<=target;old_level_r<=old_level;old_peak_r<=old_peak;old_age_r<=old_age;
  end
  if(updating&&update_phase)begin
   levels[update_index]<={1'b0,target_r}+9'd16<{1'b0,old_level_r}?old_level_r-16:target_r;
   peaks[update_index]<=target_r>=old_peak_r?target_r:old_age_r!=0?old_peak_r:old_peak_r>8?old_peak_r-8:0;
   ages[update_index]<=target_r>=old_peak_r?3'd3:old_age_r!=0?old_age_r-1'b1:0;
  end
 end
 always @(posedge clk)begin
  if(rst||!source_live)begin
   collect_bank<=0;latest_bank<=0;snapshot_bank<=0;have_window<=0;display_valid<=0;updating<=0;
   mask<=0;maximum<=0;maximum_index<=0;latest_index<=0;display_index<=0;update_index<=0;snapshot_index<=0;
   latest_valid<=0;display_peak_valid<=0;snapshot_peak_valid<=0;idle_frames<=0;
   update_phase<=0;
  end else begin
   if(incoming)begin
    if(band_idx==0)mask<=1;else mask<=mask|(16'h0001<<band_idx);
    if(wins)begin maximum<=band_mag;maximum_index<=band_idx[3:0];end
    if(complete)begin
     latest_bank<=collect_bank;collect_bank<=~collect_bank;have_window<=1;idle_frames<=0;
     latest_index<=wins?band_idx[3:0]:maximum_index;
     latest_valid<=(wins?band_mag:maximum)>10240;
    end
   end
   if(frame_tick&&!updating)begin
    snapshot_bank<=complete?collect_bank:latest_bank;update_index<=0;updating<=1;update_phase<=0;
    snapshot_index<=complete?(wins?band_idx[3:0]:maximum_index):latest_index;
    snapshot_peak_valid<=have_window&&idle_frames<5&&latest_valid;
    if(!complete&&idle_frames!=7)idle_frames<=idle_frames+1'b1;
   end
   if(updating)begin
    update_phase<=!update_phase;
    if(update_phase)begin
     if(update_index==11)begin
      updating<=0;display_valid<=1;display_index<=snapshot_index;display_peak_valid<=snapshot_peak_valid;
     end else update_index<=update_index+1'b1;
    end
   end
  end
 end
 reg [11:0] xd,yd,x_pre,y_pre;reg [7:0] height_d,peak_d,height_pre,peak_pre;reg winner_d,winner_pre;
 wire [11:0] dx=x-BAR_X;
 always @(posedge clk)begin
  x_pre<=x;y_pre<=y;xd<=x_pre;yd<=y_pre;
  height_pre<=display_valid?levels[dx[8:5]]:8'd0;
  peak_pre<=display_valid?peaks[dx[8:5]]:8'd0;
  winner_pre<=display_peak_valid&&dx[8:5]==display_index;
  height_d<=height_pre;peak_d<=peak_pre;winner_d<=winner_pre;
 end
 wire [11:0] px=xd-BAR_X,py=yd-BAR_Y;
 wire region=xd>=BAR_X&&xd<BAR_X+BAR_W&&yd>=BAR_Y&&yd<BAR_Y+BAR_H;
 wire [11:0] bottom=BAR_Y+BAR_H-15;
 wire [11:0] top=bottom-6-height_d;
 wire fill=region&&height_d!=0&&px[4:0]<20&&yd>=top&&yd<=bottom;
 wire cap=region&&display_valid&&peak_d!=0&&px[4:0]<20&&yd==bottom-6-peak_d;
 wire border=region&&(px<3||px>=BAR_W-3||py<3||py>=BAR_H-3);
 wire [11:0] fx=x-BAR_X,fy=y-(BAR_Y+BAR_H-10);
 reg [23:0] frequency;
 always @*case(fx[8:5])
  0:frequency="262";1:frequency="294";2:frequency="330";3:frequency="349";
  4:frequency="392";5:frequency="440";6:frequency="494";7:frequency="523";
  8:frequency="800";9:frequency="1k0";10:frequency="1k2";default:frequency="1k6";endcase
 wire [7:0] fc=fx[4:3]==0?frequency[23:16]:fx[4:3]==1?frequency[15:8]:frequency[7:0];
 wire [4:0] fp;
 audio_label_font_fast u_labels(.character(fc),.row(fy[2:0]),.pixels(fp));
 reg text_on,legend_on;
 wire [11:0] lx=fx-8,ly=y-BAR_Y-7;
 reg [7:0] legend_character;
 always @*case(lx[5:3])
  0:legend_character="B";1:legend_character=":";2:legend_character="O";
  3:legend_character=source_live?"N":"F";4:legend_character=source_live?" ":"F";
  default:legend_character=" ";endcase
 wire [4:0] lp;
 audio_label_font_fast u_legend(.character(legend_character),.row(ly[2:0]),.pixels(lp));
 // Two pixel stages separate glyph decoding from bit selection. The real
 // compositor supplies s1 instead of s2, keeping its total latency unchanged.
 reg [4:0] font_d,legend_d;reg [2:0] font_col_d,legend_col_d;reg font_range_d,legend_range_d;
 always @(posedge clk)begin
  font_d<=fp;legend_d<=lp;font_col_d<=fx[2:0];legend_col_d<=lx[2:0];
  font_range_d<=!rst&&fx<BAR_W&&fy<7&&fx[4:0]<24&&fx[2:0]<5;
  legend_range_d<=!rst&&lx<40&&ly<7&&lx[2:0]<5;
  text_on<=!rst&&font_range_d&&font_d[4-font_col_d];
  legend_on<=!rst&&legend_range_d&&legend_d[4-legend_col_d];
 end
 always @*begin
  bars_rgb=0;bars_alpha=0;
  if(region)begin
   bars_rgb=24'h061420;bars_alpha=150;
   if(border)begin bars_rgb=source_live?24'h2e6fa8:24'hdb7d2c;bars_alpha=210;end
   if(fill&&display_valid)begin
    bars_rgb=px[8:5]<2?24'h28c7fa:px[8:5]<10?24'h30d9b0:px[8:5]<12?24'hffb54c:24'hbb80ff;bars_alpha=255;
   end
   if(fill&&winner_d&&yd<top+2||cap)begin bars_rgb=24'hdff8ff;bars_alpha=255;end
   if(text_on)begin bars_rgb=24'ha9d3e0;bars_alpha=255;end
   if(legend_on)begin bars_rgb=source_live?24'h76e4b0:24'hffc16e;bars_alpha=255;end
  end
 end
endmodule
