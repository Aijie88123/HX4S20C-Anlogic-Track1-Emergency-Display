`timescale 1ns/1ps
module tb_temperature_compositor;
 reg [12:0] flags=0;reg [23:0] colour=0;
 wire [23:0] rgb,old_rgb;wire [7:0] alpha,old_alpha;
 text_overlay_8x8 #(.ENABLE_SUBTITLE(1),.ENABLE_TEMPERATURE_OSD(1)) dut(
  .clk(1'b0),.rst(1'b0),.temperature_status(25'h1c00163),.emergency(flags[12]),
  .custom_active(1'b0),.custom_pixel(1'b0),.custom_bar(1'b0),.startup_loading(1'b0),.startup_progress(9'd0),.blink_on(1'b0),
  .x(12'd0),.y(12'd0),.x_pre(12'd0),.y_pre(12'd0),.x_early(12'd0),.y_early(12'd0),
  .page_index(3'd0),.brightness(3'd0),.contrast(3'd0),.interval_selection(2'd0),.playback_running(1'b0),
  .elapsed_seconds(7'd0),.scroll_phase(12'd0),.scroll_phase_pre(12'd0),.feature_mask(4'd0),.res_str(72'd0),.text_rgb(rgb),.text_alpha(alpha));
 temperature_compositor_reference #(.ENABLE_SUBTITLE(1),.ENABLE_TEMPERATURE_OSD(1)) reference(
  .clk(1'b0),.rst(1'b0),.temperature_status(25'h1c00163),.emergency(flags[12]),
  .custom_active(1'b0),.custom_pixel(1'b0),.custom_bar(1'b0),.startup_loading(1'b0),.startup_progress(9'd0),.blink_on(1'b0),
  .x(12'd0),.y(12'd0),.x_pre(12'd0),.y_pre(12'd0),.x_early(12'd0),.y_early(12'd0),
  .page_index(3'd0),.brightness(3'd0),.contrast(3'd0),.interval_selection(2'd0),.playback_running(1'b0),
  .elapsed_seconds(7'd0),.scroll_phase(12'd0),.scroll_phase_pre(12'd0),.feature_mask(4'd0),.res_str(72'd0),.text_rgb(old_rgb),.text_alpha(old_alpha));
`define BOTH(signal,value) force dut.signal=value;force reference.signal=value;
 integer c,n,checks=0;
 initial begin
  `BOTH(emergency_border,flags[0])
  `BOTH(startup_bar_r,flags[1])
  `BOTH(startup_fill_r,flags[2])
  `BOTH(temperature_pixel,flags[3])
  `BOTH(glyph_pixel,flags[4])
  `BOTH(status_pixel,flags[5])
  `BOTH(banner_pixel,flags[6])
  `BOTH(in_bar,flags[7])
  `BOTH(status_bar_visible,flags[8])
  `BOTH(banner_bar_visible,flags[9])
  `BOTH(temperature_bar_visible,flags[10])
  `BOTH(startup_on,flags[11])
  `BOTH(temperature_colour,colour)
  for(c=0;c<7;c++)begin
   case(c)0:colour=0;1:colour=24'hffffff;2:colour=24'h70ffd0;3:colour=24'hffca48;
    4:colour=24'hff5656;5:colour=24'hffe0a0;6:colour=24'h123456;endcase
   for(n=0;n<8192;n++)begin flags=n;#1;
    if({rgb,alpha}!=={old_rgb,old_alpha})$fatal(1,"compositor priority flags%h colour%h got%h/%h expected%h/%h",flags,colour,rgb,alpha,old_rgb,old_alpha);
    checks++;
   end
  end
  $display("PASS: parallel text compositor/prior temperature compositor exact RGB+alpha %0d binary combinations; every priority overlap and seven foreground colours",checks);$finish;
 end
`undef BOTH
endmodule
