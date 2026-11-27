`timescale 1ns/1ps
module tb_temperature_status_dynamic;
 reg clk=0;always #6.666 clk=~clk;
 reg rst=1;reg [11:0] sx=0,sy=0,x1=0,y1=0,x2=0,y2=0,x3=0,y3=0;
 reg [2:0] page=0,brightness=0,contrast=0;reg [1:0] interval_sel=0;
 reg playing=0,loading=0,emergency=0,blink=0;reg [3:0] features=4'h4;
 reg [71:0] resolution="1280X 720";reg [31:0] random_state=32'h1234abcd;
 wire [23:0] rgb,old_rgb;wire [7:0] alpha,old_alpha;
`define PARAMS .SCREEN_W(1280),.SCREEN_H(720),.USE_BANNER_ROM(1),.ENABLE_SUBTITLE(1),.ENABLE_TEMPERATURE_OSD(1),.ENABLE_STARTUP_UI(1),.ENABLE_PERIOD_OSD(1),.DEMO_FAST_PERIODS(1),.ENABLE_PLAYBACK_OSD(1),.PIPELINED_STATUS_CHAR(1)
`define PORTS .clk(clk),.rst(rst),.temperature_status(25'h1c00163),.emergency(emergency),.custom_active(1'b0),.custom_pixel(1'b0),.custom_bar(1'b0),.startup_loading(loading),.startup_progress(9'd200),.blink_on(blink),.x(x3),.y(y3),.x_pre(x2),.y_pre(y2),.x_early(x1),.y_early(y1),.page_index(page),.brightness(brightness),.contrast(contrast),.interval_selection(interval_sel),.playback_running(playing),.elapsed_seconds(7'd0),.scroll_phase(12'd0),.scroll_phase_pre(12'd0),.feature_mask(features),.res_str(resolution)
 text_overlay_8x8 #(`PARAMS) dut(`PORTS,.text_rgb(rgb),.text_alpha(alpha));
 temperature_status_reference #(`PARAMS) reference(`PORTS,.text_rgb(old_rgb),.text_alpha(old_alpha));
`undef PARAMS
`undef PORTS
 always @(posedge clk)if(rst)begin x1<=0;y1<=0;x2<=0;y2<=0;x3<=0;y3<=0;end
 else begin x1<=sx;y1<=sy;x2<=x1;y2<=y1;x3<=x2;y3<=y2;end
 integer n,checks=0,ink=0;
 initial begin
 repeat(16)@(negedge clk);rst=0;
 for(n=0;n<60000;n++)begin
  @(negedge clk);
  random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
  if(n<40000)begin sx=976+n%288;sy=(n<20000?20:48)+(n/288)%16;end
  else begin sx=random_state%1280;sy=(random_state>>11)%720;features=n[15:12];loading=n[9];emergency=n[10];blink=n[11];end
  page=n[2:0];brightness=n[5:3];contrast=n[8:6];interval_sel=n%3;playing=n[0];
  resolution={random_state,random_state^32'h9e3779b9,8'h41};
  @(posedge clk);#1;
  // The enlarged temperature rectangle is intentionally different from
  // this historical status reference; the independent glyph test covers it.
  if(n>10 && !(x3>=20 && x3<284 && y3>=16 && y3<38))begin
   if({rgb,alpha}!=={old_rgb,old_alpha})$fatal(1,"status split dynamic cycle%0d x%0d y%0d got%h/%h expected%h/%h",n,x3,y3,rgb,alpha,old_rgb,old_alpha);
   checks++;if(alpha==255&&rgb==24'hffffff)ink++;
  end
 end
 if(checks<59000||ink<1000)$fatal(1,"status split coverage %0d/%0d",checks,ink);
 $display("PASS: split status/period registers versus original character register exact RGB+alpha %0d dynamic-input cycles outside enlarged temperature, %0d white glyph pixels; every-cycle page/B/C/period/play/resolution changes plus arbitrary modes and coordinates",checks,ink);$finish;
 end
endmodule
