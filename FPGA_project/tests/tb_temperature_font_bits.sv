`timescale 1ns/1ps
module tb_temperature_font_bits;
 reg clk=0;always #6.666 clk=~clk;
 reg [13:0] address=0,other_address=0;
 wire pixel,old_pixel,other_pixel,old_other_pixel;
 subtitle_shared_font_rom #(.ENABLE_SECOND(1)) dut(.clk(clk),.address(address),.pixel(pixel),.temperature_address(other_address),.temperature_pixel(other_pixel));
 temperature_compositor_font #(.ENABLE_SECOND(1)) reference(.clk(clk),.address(address),.pixel(old_pixel),.temperature_address(other_address),.temperature_pixel(old_other_pixel));
 integer n,checks=0;
 initial begin
  repeat(20)@(negedge clk);
  for(n=0;n<16384;n++)begin
   @(negedge clk);address=n;other_address=(n*73+119)%16384;
   @(posedge clk);#1;
   if({pixel,other_pixel}!=={old_pixel,old_other_pixel})$fatal(1,"native font bits A%h B%h got%b%b expected%b%b",address,other_address,pixel,other_pixel,old_pixel,old_other_pixel);
   checks+=2;
  end
  $display("PASS: %0d native font bit comparisons, complete16384-bit address space on each independently permuted port; original INIT and latency preserved with native byte selection",checks);$finish;
 end
endmodule
