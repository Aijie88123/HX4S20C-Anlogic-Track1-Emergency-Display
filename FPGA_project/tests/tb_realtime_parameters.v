`timescale 1ns/1ps
// Production button decoder, SD scheduler, CDC registers, colour LUT and OSD.
// The card-ready wire is fault-injected; no button/control/render logic is mocked.
// CLK_FREQ_HZ=1000 scales milliseconds to cycles while preserving all thresholds.
module tb_realtime_parameters;
reg sdclk=0,clk=0,rst=1,key_b=1,key_c=1,emergency=0,vs=1;
always #10 sdclk=~sdclk;
always #13 clk=~clk;
wire bt,ct;wire [2:0] b,c;wire [1:0] bank;wire we;wire [9:0] wa;wire [7:0] wd;
sd_card_bmp #(.CLK_FREQ_HZ(1000),.LOAD_TIMEOUT_MS(0),.BMP_STALL_TIMEOUT_MS(0)) sd(
 .clk(sdclk),.rst(rst),.key_next(key_b),.key_auto(key_c),.emergency(emergency),
 .brightness_step_toggle(bt),.contrast_step_toggle(ct),
 .bmp_width(16'd1280),.bmp_height(16'd720),.write_finish_toggle(1'b0),
 .write_req_ack(1'b0),.SD_MISO(1'b1));
display_parameter_control control(.clk(clk),.rst(rst),.emergency(emergency),.vsync(vs),
 .brightness_step_toggle(bt),.contrast_step_toggle(ct),.brightness(b),.contrast(c),.palette_bank(bank),.palette_write_enable(we),.palette_write_address(wa),.palette_write_value(wd));
reg [23:0] input_rgb=24'h4080c0;wire [23:0] colour;
video_palette_lookup lut(.clk(clk),.rst(rst),.enable(1'b1),.in_rgb(input_rgb),.bank(bank),.write_enable(we),.write_address(wa),.write_value(wd),.out_rgb(colour));
reg [11:0] x=4095,y=4095,xp=4095,yp=4095;
wire [23:0] text_rgb,reference_rgb;wire [7:0] text_alpha,reference_alpha;
reg [2:0] applied_b=4,applied_c=4;
text_overlay_8x8 #(.SCREEN_W(1280),.SCREEN_H(720)) osd(
 .clk(clk),.rst(rst),.emergency(emergency),.blink_on(1'b1),.x(x),.y(y),.x_pre(xp),.y_pre(yp),
 .page_index(3'd0),.brightness(b),.contrast(c),.elapsed_seconds(7'd0),
 .scroll_phase(12'd0),.feature_mask(4'b0100),.res_str("1280X 720"),.text_rgb(text_rgb),.text_alpha(text_alpha));
text_overlay_link_baseline #(.SCREEN_W(1280),.SCREEN_H(720)) font_reference(
 .clk(clk),.rst(rst),.emergency(emergency),.blink_on(1'b1),.x(x),.y(y),.x_pre(xp),.y_pre(yp),
 .page_index(3'd0),.brightness(applied_b),.contrast(applied_c),.elapsed_seconds(7'd0),
 .scroll_phase(12'd0),.feature_mask(4'b0100),.res_str("1280X 720"),.text_rgb(reference_rgb),.text_alpha(reference_alpha));
integer b_events=0,c_events=0,b_short=0,c_short=0,pixels=0,frames=0;
reg last_bt=0,last_ct=0;
always @(posedge sdclk)begin
 #1;
 if(rst)begin last_bt=0;last_ct=0;end
 else begin
  if(bt!==last_bt)b_events=b_events+1;
  if(ct!==last_ct)c_events=c_events+1;
  if(sd.key_next_press)b_short=b_short+1;
  if(sd.key_auto_press)c_short=c_short+1;
  last_bt=bt;last_ct=ct;
 end
end
// Detect every unrequested mid-frame register change, not just checkpoints.
always @(posedge clk)begin
 #2;
 if(!rst&&(b!==applied_b||c!==applied_c))
  $fatal(1,"uncommitted parameters B=%d C=%d expected=%d/%d",b,c,applied_b,applied_c);
end
task sd_cycles;input integer n;begin repeat(n)@(negedge sdclk);end endtask
task hold_keys;input integer which,n,expected_steps;
 integer eb0,ec0,bs0,cs0;
 begin
  eb0=b_events;ec0=c_events;bs0=b_short;cs0=c_short;
  @(negedge sdclk);if(which&1)key_b=0;if(which&2)key_c=0;
  sd_cycles(n);key_b=1;key_c=1;sd_cycles(40);
  if(b_events-eb0!==((which&1)?expected_steps:0)||c_events-ec0!==((which&2)?expected_steps:0))
   $fatal(1,"long/repeat count which=%d n=%d B=%d C=%d",which,n,b_events-eb0,c_events-ec0);
  if(b_short!=bs0||c_short!=cs0)$fatal(1,"long release leaked short operation");
 end
endtask
task commit;input [2:0] nb,nc;
 begin
  @(negedge clk);vs=1;repeat(600)@(negedge clk);vs=0;
  @(posedge clk);#1;
  if(!emergency)begin applied_b=nb;applied_c=nc;end
  if(b!==applied_b||c!==applied_c)$fatal(1,"frame commit mismatch");
  repeat(4)@(negedge clk);vs=1;repeat(4)@(negedge clk);frames=frames+1;
 end
endtask
function [7:0] expected_channel;
 input [7:0] v;input [2:0] bb,cc;integer vi,bi,ci,scaled,adjusted;
 begin vi=v;bi=bb;ci=cc;scaled=(vi-128)*(ci+4);adjusted=128+(scaled>>>3)+(bi-4)*12;
  expected_channel=adjusted<0?0:(adjusted>255?255:adjusted);
 end
endfunction
task verify_render;
 integer channel_value,which,row,col,index;reg [23:0] wanted;reg [7:0] glyph;
 begin
  // Independent signed arithmetic at the real applied register outputs.
  for(channel_value=0;channel_value<256;channel_value=channel_value+1)begin
   @(negedge clk);input_rgb={channel_value[7:0],8'hff-channel_value[7:0],channel_value[7:0]^8'h80};@(posedge clk);#1;
   wanted={expected_channel(input_rgb[23:16],applied_b,applied_c),
           expected_channel(input_rgb[15:8],applied_b,applied_c),
           expected_channel(input_rgb[7:0],applied_b,applied_c)};
   if(colour!==wanted)$fatal(1,"colour/parameter mismatch input=%h result=%h expected=%h",input_rgb,colour,wanted);
  end
  // Verify every pixel of both displayed parameter digits against frozen glyphs.
  for(which=0;which<2;which=which+1)begin
   index=which?7:4;
   for(row=0;row<8;row=row+1)for(col=0;col<8;col=col+1)begin
    @(negedge clk);xp=976+index*16+col*2;yp=20+row*2;
    @(posedge clk);#1;x=xp;y=yp;#1;
    glyph=font_reference.font_row(8'h30+(which?applied_c:applied_b),row);
    if(text_rgb!==reference_rgb||text_alpha!==reference_alpha)
     $fatal(1,"OSD differs from independent applied-state glyph");
    if(text_rgb!==(glyph[7-col]?24'hffffff:24'h12385a)||
       text_alpha!==(glyph[7-col]?8'd255:8'd180))
     $fatal(1,"OSD digit B=%d C=%d row=%d col=%d",b,c,row,col);
    pixels=pixels+1;
   end
  end
 end
endtask
integer i,b0,c0;
reg before_bt;
initial begin
 force sd.sd_init_done=1'b0;
 sd_cycles(10);rst=0;sd_cycles(30);verify_render;
 // Electrical contact bounce shorter than the production six-cycle debounce.
 repeat(5)begin key_b=0;key_c=0;sd_cycles(2);key_b=1;key_c=1;sd_cycles(2);end
 sd_cycles(30);
 if(b_events||c_events||b_short||c_short)$fatal(1,"contact bounce accepted");
 key_b=0;sd_cycles(40);key_b=1;sd_cycles(30);
 key_c=0;sd_cycles(40);key_c=1;sd_cycles(30);
 if(b_short!=1||c_short!=1||b_events||c_events)$fatal(1,"short/long classification changed");
 $display("PASS: production debounce rejects bounce; S2/S3 short operations remain separate from parameters");
 hold_keys(1,1420,1);verify_render;commit(5,4);verify_render;
 // A high source toggle must survive both loss and recovery of card-ready.
 if(bt!==1'b1)$fatal(1,"expected odd brightness toggle");
 b0=b_events;c0=c_events;
 force sd.sd_init_done=1'b1;sd_cycles(60);
 force sd.sd_init_done=1'b0;sd_cycles(60);
 if(b_events!=b0||c_events!=c0||bt!==1'b1)$fatal(1,"card restart creates a phantom parameter event");
 commit(5,4);verify_render;
 hold_keys(2,1420,1);verify_render;commit(5,5);verify_render;
 hold_keys(3,1420,1);verify_render;commit(6,6);verify_render;
 $display("PASS: controls operate while card initialization is incomplete; card restart preserves toggles and applied B/C; both parameters commit at VS falling");
 hold_keys(1,2020,3);verify_render;commit(1,6);verify_render;
 hold_keys(2,3520,8);commit(1,6);verify_render;
 for(i=0;i<8;i=i+1)begin
  hold_keys(3,1420,1);verify_render;
  commit((applied_b+1)&7,(applied_c+1)&7);verify_render;
 end
 $display("PASS: 1400-cycle first hold, 300-cycle repeat, modulo-eight wrap and every displayed B/C digit 0..7");
 emergency=1;sd_cycles(30);hold_keys(3,1420,1);commit(2,7);
 emergency=0;sd_cycles(30);commit(1,6);verify_render;
 hold_keys(3,1420,1);commit(2,7);verify_render;
 $display("PASS: emergency consumes and ignores local adjustment events without delayed changes after return");
 // A genuine source event reaches its first usable CDC cycle at VS falling.
 before_bt=bt;@(negedge sdclk);key_b=0;
 wait(bt!==before_bt);
 repeat(2)begin @(posedge clk);#1;end
 @(negedge clk);vs=0;
 @(posedge clk);#1;
 if(b!==2||c!==7)$fatal(1,"unprepared bank exposed at coincident event boundary");
 key_b=1;sd_cycles(40);@(negedge clk);vs=1;verify_render;commit(3,7);verify_render;
 $display("PASS: source event at VS waits for complete inactive bank, then updates colour and OSD together");
 @(negedge clk);rst=1;applied_b=4;applied_c=4;vs=1;sd_cycles(20);
 rst=0;sd_cycles(30);commit(4,4);verify_render;
 $display("PASS: button -> SD-independent event -> asynchronous CDC -> frame registers -> colour LUT/OSD chain; %0d glyph pixels, %0d frame commits; global reset restores B4/C4",pixels,frames);
 $finish;
end
initial begin #5000000;$fatal(1,"parameter-chain timeout");end
endmodule
