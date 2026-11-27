`timescale 1ns/1ps
// Only PLL pins and the physical memory are modeled. Parser, scaler, FIFOs,
// SDRAM request arbitration and frame completion are the production RTL.
module sys_pll(input refclk,reset,output reg clk0_out=0,clk1_out=0,clk2_out=1,extlock=0);
 always #10 clk0_out=~clk0_out;always #4 begin clk1_out=~clk1_out;clk2_out=~clk2_out;end
 initial #400 extlock=1;
endmodule
