`timescale 1ns/1ps
// Only PLL pins and the physical memory are modeled. Parser, scaler, FIFOs,
// SDRAM request arbitration and frame completion are the production RTL.
module sys_pll(input refclk,reset,output reg clk0_out=0,clk1_out=0,clk2_out=1,extlock=0);
 always #10 clk0_out=~clk0_out;always #4 begin clk1_out=~clk1_out;clk2_out=~clk2_out;end
 initial #400 extlock=1;
endmodule
module sdram(input Clk,Clk_sft,Rst,output reg Sdr_init_done=0,output Sdr_init_ref_vld,Sdr_busy,
 input App_wr_en,input [20:0] App_wr_addr,input [3:0] App_wr_dm,input [31:0] App_wr_din,
 input App_rd_en,input [20:0] App_rd_addr,output reg Sdr_rd_en=0,output reg [31:0] Sdr_rd_dout=0);
 reg [31:0] ram[0:2097151];integer writes=0;integer init_count=0;
 assign Sdr_init_ref_vld=0;assign Sdr_busy=0;
 always @(posedge Clk)begin
  if(Rst)begin init_count<=0;Sdr_init_done<=0;Sdr_rd_en<=0;end
  else begin
   if(init_count<32)init_count<=init_count+1;else Sdr_init_done<=1;
   Sdr_rd_en<=App_rd_en;if(App_rd_en)Sdr_rd_dout<=ram[App_rd_addr];
   if(App_wr_en)begin if(App_wr_addr>=2097152)$fatal(1,"FAIL: B compact source cache address");ram[App_wr_addr]<=App_wr_din;writes<=writes+1;end
  end
 end
endmodule
