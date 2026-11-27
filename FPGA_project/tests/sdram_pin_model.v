`timescale 1ns/1ps
// Independent command-level SDR SDRAM model for the supplied encrypted
// controller. Functional BL4/CL3 and masked data only; not analog/timing signoff.
module sdram_pin_model(input clk,ras,cas,we,input [10:0] address,input [1:0] bank,
 input [3:0] dm,inout [31:0] dq);
 reg [31:0] memory[0:2097151];reg [10:0] row[0:3];
 reg [20:0] wp,rp;reg [2:0] write_left=0,read_left=0;
 reg [31:0] pipe0,pipe1,pipe2,out_data;reg [2:0] valids=0;reg drive=0;
 integer k;wire [20:0] index={row[bank],bank,address[7:0]};
 assign dq=drive?out_data:32'bz;
 always @(posedge clk)begin
  valids<={valids[1:0],1'b0};pipe1<=pipe0;pipe2<=pipe1;
  drive<=#1 valids[1];out_data<=#1 pipe1;
  if({ras,cas,we}==3'b011)row[bank]<=address;
  if({ras,cas,we}==3'b100 || write_left!=0)begin
   for(k=0;k<4;k=k+1)if(!dm[k])memory[({ras,cas,we}==3'b100 ? index : wp)][k*8 +:8]<=dq[k*8 +:8];
   if({ras,cas,we}==3'b100)begin wp<=index+1;write_left<=3;end
   else begin wp<=wp+1;write_left<=write_left-1'b1;end
  end
  if({ras,cas,we}==3'b101 || read_left!=0)begin
   pipe0<=memory[{ras,cas,we}==3'b101 ? index : rp];valids[0]<=1;
   if({ras,cas,we}==3'b101)begin rp<=index+1;read_left<=3;end
   else begin rp<=rp+1;read_left<=read_left-1'b1;end
  end
 end
endmodule
