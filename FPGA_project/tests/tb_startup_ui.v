`timescale 1ns/1ps
module tb_startup_ui;
 reg clk=0,rst=1,loading=1;always #5 clk=~clk;
 reg [11:0] xp=0,yp=0,x=0,y=0;reg [8:0] progress=0;
 wire [23:0] rgb,base;wire [7:0] alpha,base_alpha;
 text_overlay_8x8 #(.SCREEN_W(1280),.SCREEN_H(720),.ENABLE_PERIOD_OSD(1),.ENABLE_STARTUP_UI(1)) dut(
  .clk(clk),.rst(rst),.emergency(1'b0),.startup_loading(loading),.startup_progress(progress),.blink_on(1'b0),
  .x(x),.y(y),.x_pre(xp),.y_pre(yp),.page_index(3'd2),.brightness(3'd4),.contrast(3'd4),
  .interval_selection(2'd0),.elapsed_seconds(7'd0),.scroll_phase(12'd0),.scroll_phase_pre(12'd0),.feature_mask(4'hf),
  .res_str(" 640X 480"),.text_rgb(rgb),.text_alpha(alpha));
 text_overlay_8x8 #(.SCREEN_W(1280),.SCREEN_H(720),.ENABLE_PERIOD_OSD(1)) reference(
  .clk(clk),.rst(rst),.emergency(1'b0),.startup_loading(1'b0),.startup_progress(9'd0),.blink_on(1'b0),
  .x(x),.y(y),.x_pre(xp),.y_pre(yp),.page_index(3'd2),.brightness(3'd4),.contrast(3'd4),
  .interval_selection(2'd0),.elapsed_seconds(7'd0),.scroll_phase(12'd0),.scroll_phase_pre(12'd0),.feature_mask(4'hf),
  .res_str(" 640X 480"),.text_rgb(base),.text_alpha(base_alpha));
 integer count=0,px,py,level,idx,col,row;reg [63:0] glyph;reg bit_on;
 function [63:0] caption_glyph(input integer n);
  begin case(n)
   0:caption_glyph=64'h4040404040407e00; // L
   1:caption_glyph=64'h3c42424242423c00; // O
   2,10:caption_glyph=64'h1824427e42424200; // A
   3:caption_glyph=64'h7844424242447800; // D
   4,8:caption_glyph=64'h7e18181818187e00; // I
   5:caption_glyph=64'h4262524a46424200; // N
   6,11:caption_glyph=64'h3c42404e42423c00; // G
   9:caption_glyph=64'h42665a4242424200; // M
   12:caption_glyph=64'h7e40407c40407e00; // E
   default:caption_glyph=0;
  endcase end
 endfunction
 task sample(input integer xx,yy);
  begin
   @(negedge clk);xp=xx;yp=yy;x=xx;y=yy;
   @(posedge clk);#1;
   count=count+1;
   if(loading && yy>=384 && yy<396 && xx>=440 && xx<840)begin
    if(alpha!==255 || rgb!==(xx-440<progress?24'h31d8cb:24'h203a52))
     $fatal(1,"FAIL: progress pixel x=%d y=%d p=%d rgb=%h a=%d",xx,yy,progress,rgb,alpha);
   end else if(loading && xx>=976 && xx<1264 && yy>=20 && yy<36)begin
    idx=(xx-976)/16;col=((xx-976)%16)/2;row=(yy-20)/2;
    glyph=caption_glyph(idx);bit_on=(glyph>>(63-row*8-col))&1;
    if(bit_on && (rgb!==24'hffffff||alpha!==255))$fatal(1,"FAIL: caption glyph idx=%d row=%d col=%d",idx,row,col);
    if(!bit_on && alpha===255)$fatal(1,"FAIL: caption extra glyph pixel");
   end else if(rgb!==base || alpha!==base_alpha)
    $fatal(1,"FAIL: startup UI altered existing text pixel x=%d y=%d loading=%b",xx,yy,loading);
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst=0;
  for(level=0;level<4;level=level+1)begin
   case(level)0:progress=0;1:progress=1;2:progress=200;3:progress=400;endcase
   for(py=382;py<398;py=py+1)for(px=438;px<842;px=px+1)sample(px,py);
  end
  for(py=14;py<65;py=py+1)for(px=966;px<1274;px=px+1)sample(px,py);
  loading=0;repeat(4)@(negedge clk);
  for(py=0;py<720;py=py+1)for(px=0;px<1280;px=px+1)sample(px,py);
  $display("PASS: startup LOADING IMAGE glyphs independently decoded; empty/1/50%%/complete actual-data progress and borders; loading removal leaves every existing 1280x720 text/parameter/period/banner pixel unchanged; checked=%0d",count);
  $finish;
 end
endmodule
