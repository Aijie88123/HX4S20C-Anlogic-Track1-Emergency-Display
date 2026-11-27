`timescale 1ns/1ps
// Compare the split character/BRAM path against the original one-stage
// status decoder under a real advancing coordinate pipeline.
module tb_temperature_status_pipeline;
reg clk=0;always #6.666 clk=~clk;
reg rst=1;
reg [11:0] scan_x=0,scan_y=0,x1=0,y1=0,x2=0,y2=0,x3=0,y3=0;
integer cfg=0,compared=0,status_pixels=0,period_pixels=0;
wire [23:0] ref_rgb,pipe_rgb;wire [7:0] ref_alpha,pipe_alpha;
wire [71:0] resolution=cfg[0]?"1280X 720":" 640X 480";
genvar g;
generate for(g=0;g<2;g=g+1)begin: variant
 wire [23:0] rgb;wire [7:0] alpha;
 text_overlay_8x8 #(.SCREEN_W(1280),.SCREEN_H(720),.ENABLE_SUBTITLE(1),
   .USE_BANNER_ROM(1),.ENABLE_PERIOD_OSD(1),.DEMO_FAST_PERIODS(1),
   .ENABLE_PLAYBACK_OSD(1),.ENABLE_STARTUP_UI(1),.PIPELINED_STATUS_CHAR(g)) text(
   .clk(clk),.rst(rst),.temperature_status(25'd0),.emergency(1'b0),
   .custom_active(1'b0),.custom_pixel(1'b0),.custom_bar(1'b0),
   .startup_loading(cfg==7),.startup_progress(9'd200),.blink_on(1'b0),
   .x(x3),.y(y3),.x_pre(x2),.y_pre(y2),.x_early(x1),.y_early(y1),
   .page_index(cfg[2:0]),.brightness(cfg[2:0]),.contrast(~cfg[2:0]),
   .interval_selection(cfg%3),.playback_running(cfg[0]),.elapsed_seconds(7'd0),
   .scroll_phase(12'd0),.scroll_phase_pre(12'd0),.feature_mask(4'h4),
   .res_str(resolution),.text_rgb(rgb),.text_alpha(alpha));
 if(g==0)begin assign ref_rgb=rgb;assign ref_alpha=alpha;end
 else begin assign pipe_rgb=rgb;assign pipe_alpha=alpha;end
end endgenerate
initial begin repeat(5)@(negedge clk);rst=0;end
always @(posedge clk)if(!rst)begin
 x1<=scan_x;y1<=scan_y;x2<=x1;y2<=y1;x3<=x2;y3<=y2;
 if(scan_x==1299)begin scan_x<=0;
  if(scan_y==87)begin scan_y<=0;cfg<=cfg+1;end else scan_y<=scan_y+1'b1;
 end else scan_x<=scan_x+1'b1;
end
always @(negedge clk)if(!rst)begin
 if(cfg<8 && scan_y!=0)begin
  if({pipe_rgb,pipe_alpha}!=={ref_rgb,ref_alpha})
   $fatal(1,"status pipeline cfg%0d x%0d y%0d got%h/%h expected%h/%h",cfg,x3,y3,pipe_rgb,pipe_alpha,ref_rgb,ref_alpha);
  compared=compared+1;
  if(x3>=976&&x3<1264&&y3>=20&&y3<36)status_pixels++;
  if(x3>=976&&x3<1136&&y3>=48&&y3<64)period_pixels++;
 end
 if(cfg==8)begin
  if(compared<900000||status_pixels!=36864||period_pixels!=20480)$fatal(1,"status coverage %0d %0d %0d",compared,status_pixels,period_pixels);
  $display("PASS: status character pipeline/reference exact RGB+alpha %0d pixels; status %0d period/playback %0d; all eight B/C/page values, three periods, PLAY/PAUSE, both resolutions, loading",compared,status_pixels,period_pixels);
  $finish;
 end
end
endmodule
