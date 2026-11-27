`timescale 1ns/1ps
module tb_temperature_emergency_font;
 reg clk=0;always #6.666 clk=~clk;
 reg rst=1;reg [11:0] scan_x=472,scan_y=332,x1=0,y1=0,x2=0,y2=0,x3=0,y3=0;
 integer cfg=0,compared=0,glyphs=0,cycles=0;
 wire [23:0] rgb,old_rgb;wire [7:0] alpha,old_alpha;
 text_overlay_8x8 #(.SCREEN_W(1280),.SCREEN_H(720),.USE_BANNER_ROM(1),.ENABLE_SUBTITLE(1),.ENABLE_TEMPERATURE_OSD(1)) dut(
  .clk(clk),.rst(rst),.temperature_status(25'h1c00163),.emergency(cfg[0]),
  .custom_active(1'b0),.custom_pixel(1'b0),.custom_bar(1'b0),.startup_loading(1'b0),.startup_progress(9'd0),
  .blink_on(cfg[1]),.x(x3),.y(y3),.x_pre(x2),.y_pre(y2),.x_early(x1),.y_early(y1),
  .page_index(3'd0),.brightness(3'd4),.contrast(3'd4),.interval_selection(2'd0),.playback_running(1'b1),
  .elapsed_seconds(7'd0),.scroll_phase(12'd0),.scroll_phase_pre(12'd0),.feature_mask(4'd0),.res_str("1280X 720"),
  .text_rgb(rgb),.text_alpha(alpha));
 temperature_parent_text #(.SCREEN_W(1280),.SCREEN_H(720),.USE_BANNER_ROM(1),.ENABLE_SUBTITLE(1)) reference(
  .clk(clk),.rst(rst),.emergency(cfg[0]),.custom_active(1'b0),.custom_pixel(1'b0),.custom_bar(1'b0),
  .startup_loading(1'b0),.startup_progress(9'd0),.blink_on(cfg[1]),.x(x3),.y(y3),.x_pre(x2),.y_pre(y2),
  .page_index(3'd0),.brightness(3'd4),.contrast(3'd4),.interval_selection(2'd0),.playback_running(1'b1),
  .elapsed_seconds(7'd0),.scroll_phase(12'd0),.scroll_phase_pre(12'd0),.feature_mask(4'd0),.res_str("1280X 720"),
  .text_rgb(old_rgb),.text_alpha(old_alpha));
 initial begin repeat(5)@(negedge clk);rst=0;end
 always @(posedge clk)if(!rst)begin
  cycles<=cycles+1;x1<=scan_x;y1<=scan_y;x2<=x1;y2<=y1;x3<=x2;y3<=y2;
  if(scan_x==815)begin scan_x<=472;
   if(scan_y==391)begin scan_y<=332;cfg<=cfg+1;end else scan_y<=scan_y+1'b1;
  end else scan_x<=scan_x+1'b1;
 end
 always @(negedge clk)if(!rst&&cycles>4)begin
  if({rgb,alpha}!=={old_rgb,old_alpha})$fatal(1,"shared emergency font cfg%0d x%0d y%0d got%h/%h expected%h/%h",cfg,x3,y3,rgb,alpha,old_rgb,old_alpha);
  compared++;
  if(cfg[0]&&alpha==255&&rgb==24'hffffff)glyphs++;
  if(cfg==4)begin
   if(compared<82000||glyphs<3000)$fatal(1,"glyph coverage %0d/%0d",compared,glyphs);
   $display("PASS: shared native emergency font/prior published compositor exact RGB+alpha %0d pixels, %0d glyph pixels; real coordinate stages, normal/emergency/blink combinations",compared,glyphs);$finish;
  end
 end
endmodule
