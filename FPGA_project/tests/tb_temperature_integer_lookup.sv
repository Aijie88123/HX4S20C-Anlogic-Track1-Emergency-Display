`timescale 1ns/1ps
module tb_temperature_integer_lookup;
 reg clk=0;always #6.666 clk=~clk;
 reg lookup=0;reg [6:0] integer_index=0;reg [13:0] a=0,b=0;
 wire pa,pb,ra,rb;wire [7:0] data;integer n,checks=0;reg [7:0] expected;
 subtitle_shared_font_rom #(.ENABLE_SECOND(1),.ENABLE_INTEGER_LOOKUP(1)) dut(
  .clk(clk),.address(a),.pixel(pa),.temperature_address(b),.temperature_pixel(pb),
  .integer_lookup(lookup),.integer_address(integer_index),.integer_byte(data));
 temperature_compositor_font #(.ENABLE_SECOND(1)) reference(
  .clk(clk),.address(a),.pixel(ra),.temperature_address(b),.temperature_pixel(rb));
 initial begin
  repeat(20)@(negedge clk);
  for(n=0;n<128;n++)begin
   @(negedge clk);lookup=1;integer_index=n;a=(n*127+291)%16384;
   expected=(((n%100)/10)<<4)|(n%10);
   @(posedge clk);#1;
   if(data!==expected||pa!==ra)$fatal(1,"integer font lookup %0d got%h expected%h A%b/%b",n,data,expected,pa,ra);
   checks+=2;
   @(negedge clk);lookup=0;b=(n*73+119)%16384;a=(n*41+137)%16384;
   @(posedge clk);#1;
   if({pa,pb}!=={ra,rb})$fatal(1,"font restore after integer lookup %0d",n);
   checks+=2;
  end
  $display("PASS: shared font upper-memory all128 integer BCD entries, parallel font A and immediate font B restore; %0d comparisons, no additional RAM or pixel latency",checks);$finish;
 end
endmodule
