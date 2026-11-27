`timescale 1ns/1ps
module tb_external_spectrum_display;
 reg clk=0;always #6.667 clk=~clk;
 reg rst=1,tick=0,valid=0,live=1;reg [4:0] band=0;reg [15:0] power=0;reg [11:0] x=0,y=0;
 wire [23:0] color,reference_color;wire [7:0] alpha,reference_alpha;
 audio_spectrum_overlay #(.N_BANDS(12),.BAR_W(384),.BAR_H(160),.BAR_X(852),.BAR_Y(484),
  .PITCH_DETAIL(1),.HEIGHT_SCALE_13_8(1),.EXTERNAL_SOURCE(1)) dut(
  .clk(clk),.rst(rst),.frame_tick(tick),.band_valid(valid),.band_idx(band),.band_mag(power),
  .source_live(live),.x(x),.y(y),.bars_rgb(color),.bars_alpha(alpha));
 audio_spectrum_reference #(.N_BANDS(12),.BAR_W(384),.BAR_H(160),.BAR_X(852),.BAR_Y(484),
  .PITCH_DETAIL(1),.HEIGHT_SCALE_13_8(1)) reference(
  .clk(clk),.rst(rst),.frame_tick(tick),.band_valid(valid),.band_idx(band),.band_mag(power),
  .x(x),.y(y),.bars_rgb(reference_color),.bars_alpha(reference_alpha));
 task push(input integer index);
  begin @(negedge clk);valid=1;band=index;power=4000+index*1700;@(negedge clk);valid=0;end
 endtask
 task frame;
  begin @(negedge clk);tick=1;@(negedge clk);tick=0;end
 endtask
 task pixel(input integer px,input integer py);
  begin @(negedge clk);x=px;y=py;@(negedge clk);end
 endtask
 integer i,j,checked=0;
 initial begin
  #100;rst=0;
  for(i=0;i<6;i=i+1)push(i);
  frame;
  for(i=0;i<12;i=i+1)if(dut.display_level[i]!==0)$fatal(1,"Partial remote window leaked to display");
  for(i=6;i<12;i=i+1)push(i);
  frame;
  for(i=848;i<1240;i=i+1)for(j=480;j<648;j=j+1)begin
   pixel(i,j);
   // The new source legend is the only intentional online pixel difference.
   if(!(i>=860 && i<900 && j>=491 && j<498))begin
    if(color!==reference_color || alpha!==reference_alpha)$fatal(1,"Remote panel changed pixel %0d,%0d",i,j);
    checked=checked+1;
   end
  end
  pixel(860,491);if(color!==24'h76E4B0 || alpha!==255)$fatal(1,"B:ON legend missing");
  live=0;repeat(3)@(negedge clk);frame;
  for(i=0;i<12;i=i+1)if(dut.display_level[i]!==0)$fatal(1,"Offline retained old spectrum");
  pixel(852,484);if(color!==24'hDB7D2C)$fatal(1,"Offline panel indicator missing");
  pixel(860,491);if(color!==24'hFFC16E || alpha!==255)$fatal(1,"B:OFF legend missing");
  live=1;
  for(i=0;i<6;i=i+1)push(i);frame;
  for(i=0;i<12;i=i+1)if(dut.display_level[i]!==0)$fatal(1,"Reconnect committed a partial window");
  for(i=6;i<12;i=i+1)push(i);frame;
  if(dut.display_level[11]==0 || !dut.display_peak_valid)$fatal(1,"Reconnect complete window/peak missing");
  $display("PASS: external spectrum complete-window/vblank commit, %0d unchanged panel pixels, original height/peak/pixel latency, B:ON/B:OFF and reconnect",checked);$finish;
 end
endmodule
