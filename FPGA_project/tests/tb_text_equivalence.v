`timescale 1ns/1ps
module tb_text_equivalence;
reg clk=0,rst=1;always #5 clk=~clk;
reg emergency=0,startup=0,blink=0,playing=0;reg [8:0] progress=0;
reg [11:0] x=0,y=0,xp=0,yp=0,scroll=0;reg [2:0] page=0,brightness=0,contrast=0;
reg [1:0] interval=0;reg [6:0] seconds=0;reg [3:0] mask=0;
wire [23:0] actual,reference;wire [7:0] aa,ra;
text_overlay_8x8 #(.SCREEN_W(1280),.SCREEN_H(720),.USE_BANNER_ROM(1),.ENABLE_PERIOD_OSD(1),.ENABLE_PLAYBACK_OSD(1),.ENABLE_STARTUP_UI(1),.CLK_FREQ_HZ(1000)) dut(.clk(clk),.rst(rst),.emergency(emergency),.startup_loading(startup),.startup_progress(progress),.blink_on(blink),.x(x),.y(y),.x_pre(xp),.y_pre(yp),.page_index(page),.brightness(brightness),.contrast(contrast),.interval_selection(interval),.playback_running(playing),.elapsed_seconds(seconds),.scroll_phase(scroll),.scroll_phase_pre(scroll),.feature_mask(mask),.res_str(72'h313238305820373230),.text_rgb(actual),.text_alpha(aa));
text_overlay_8x8_reference #(.SCREEN_W(1280),.SCREEN_H(720),.USE_BANNER_ROM(1),.ENABLE_PERIOD_OSD(1),.ENABLE_PLAYBACK_OSD(1),.ENABLE_STARTUP_UI(1),.CLK_FREQ_HZ(1000)) ref_model(.clk(clk),.rst(rst),.emergency(emergency),.startup_loading(startup),.startup_progress(progress),.blink_on(blink),.x(x),.y(y),.x_pre(xp),.y_pre(yp),.page_index(page),.brightness(brightness),.contrast(contrast),.interval_selection(interval),.playback_running(playing),.elapsed_seconds(seconds),.scroll_phase(scroll),.scroll_phase_pre(scroll),.feature_mask(mask),.res_str(72'h313238305820373230),.text_rgb(reference),.text_alpha(ra));
integer f,xx,yy,checked=0;
initial begin
repeat(4)@(negedge clk);rst=0;
for(f=0;f<4;f=f+1)begin
emergency=f[0];startup=f[1];blink=!f[1];playing=!f[1];interval=f;page=f;brightness=f+2;contrast=7-f;seconds=f*17;
for(yy=0;yy<720;yy=yy+1)for(xx=0;xx<1280;xx=xx+1)begin
@(negedge clk);x=xx;y=yy;xp=xx==1279?0:xx+1;yp=xx==1279?yy+1:yy;mask=yy[5:2];scroll=yy*3;progress=yy%401;
@(posedge clk);#1;
if({actual,aa}!=={reference,ra})$fatal(1,"text mismatch frame=%0d x=%0d y=%0d got=%h/%h expected=%h/%h",f,xx,yy,actual,aa,reference,ra);
checked=checked+1;
end
end
$display("PASS: %0d exact RGB/alpha pixels match accepted text overlay across normal/emergency, border blinking, startup progress, every feature mask, status, timer, scrolling and PLAY/PAUSE; unchanged output latency",checked);$finish;
end
initial begin #100000000;$fatal(1,"text equivalence timeout");end
endmodule
