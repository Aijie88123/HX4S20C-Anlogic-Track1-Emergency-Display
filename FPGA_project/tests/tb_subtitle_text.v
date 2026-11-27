`timescale 1ns/1ps
module tb_subtitle_text #(parameter W=1280);
reg clk=0,rst=1;always #6.667 clk=~clk;
reg [11:0] x=0,y=0;reg [23:0] bcd=0;reg [3:0] mode=0;reg emergency=0;
wire [23:0] oldrgb,newrgb;wire [7:0] oldalpha,newalpha;
subtitle_parent_text #(.SCREEN_W(W),.SCREEN_H(720),.USE_BANNER_ROM(1),.ENABLE_PERIOD_OSD(1),.DEMO_FAST_PERIODS(1),.ENABLE_PLAYBACK_OSD(1)) original(.clk(clk),.rst(rst),.emergency(emergency),.startup_loading(1'b0),.startup_progress(9'd0),.blink_on(1'b1),.x(x),.y(y),.x_pre(x),.y_pre(y),.page_index(mode[2:0]),.brightness(mode[2:0]),.contrast(~mode[2:0]),.interval_selection(mode[1:0]),.playback_running(mode[0]),.elapsed_seconds(7'd59),.scroll_phase(12'd1280),.scroll_phase_pre(12'd1280),.feature_mask(4'hf),.res_str("1280x720 "),.text_rgb(oldrgb),.text_alpha(oldalpha));
text_overlay_8x8 #(.ENABLE_SUBTITLE(1),.SCREEN_W(W),.SCREEN_H(720),.USE_BANNER_ROM(1),.ENABLE_PERIOD_OSD(1),.DEMO_FAST_PERIODS(1),.ENABLE_PLAYBACK_OSD(1)) optimized(.clk(clk),.rst(rst),.emergency(emergency),.startup_loading(1'b0),.startup_progress(9'd0),.blink_on(1'b1),.x(x),.y(y),.x_pre(x),.y_pre(y),.page_index(mode[2:0]),.brightness(mode[2:0]),.contrast(~mode[2:0]),.interval_selection(mode[1:0]),.playback_running(mode[0]),.elapsed_seconds(7'd59),.scroll_phase(12'd1280),.scroll_phase_pre(12'd1280),.feature_mask(4'hf),.res_str("1280x720 "),.custom_active(1'b0),.custom_pixel(1'b0),.custom_bar(1'b0),.text_rgb(newrgb),.text_alpha(newalpha));
reg [13:0] fontaddr=0;wire fontpx;reg [7:0] glyph;integer fi;
subtitle_shared_font_rom fullfont(.clk(clk),.address(fontaddr),.pixel(fontpx));
integer xx,yy,m,checked=0;
initial begin repeat(5)@(negedge clk);
for(fi=0;fi<16384;fi=fi+1)begin @(negedge clk);fontaddr=fi;@(posedge clk);#1;glyph=original.font_row(fi>>6,(fi>>3)&7);if(fontpx!==glyph[7-(fi&7)])$fatal(1,"native font INIT mismatch %0d",fi);end
rst=0;
force original.displayed_bcd=bcd;force optimized.displayed_bcd=bcd;
for(m=0;m<17;m=m+1)begin mode=m;emergency=m==16;bcd={6{mode}};
for(yy=0;yy<68;yy=yy+1)for(xx=0;xx<W;xx=xx+1)begin
 @(negedge clk);x=xx;y=yy;@(posedge clk);#1;
 if({newrgb,newalpha}!=={oldrgb,oldalpha})$fatal(1,"timestamp/status mismatch width%0d pattern%0d x%0d y%0d old%h/%0d new%h/%0d",W,m,x,y,oldrgb,oldalpha,newrgb,newalpha);
 checked=checked+1;end end
$display("PASS: explicit native INIT16384bits and shared font same registered RGB/alpha as immutable parent: width%0d, all16 BCD digit codes/date glyphs/status/fast periods/emergency, %0d pixels",W,checked);$finish;end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
