`timescale 1ns/1ps
// Standard-speed single-master 1-Wire. Only drive_low=1 drives the bus.
module onewire_slot #(parameter integer CLK_HZ=25000000)(
 input clk,rst,dq_in,start,input [1:0] operation,input write_bit,
 output reg drive_low,output reg busy,done,read_bit,output reg [2:0] error);
 localparam integer US=CLK_HZ/1000000;
 localparam integer CW=$clog2(1000*US+4);
 localparam [1:0] RESET=0,WRITE=1,READ=2;
 (* ASYNC_REG="TRUE" *) reg dq_meta,dq_sync;
 reg [CW-1:0] count;reg [1:0] op;reg data,presence,stuck;
 always @(posedge clk or posedge rst)
  if(rst)begin dq_meta<=1;dq_sync<=1;end
  else begin dq_meta<=dq_in;dq_sync<=dq_meta;end
 always @(posedge clk or posedge rst)
  if(rst)begin drive_low<=0;busy<=0;done<=0;read_bit<=1;error<=0;count<=0;op<=0;data<=0;presence<=0;stuck<=0;end
  else begin
   done<=0;
   if(!busy)begin
    drive_low<=0;
    if(start)begin
     error<=0;count<=0;op<=operation;data<=write_bit;presence<=0;stuck<=0;
     if(operation==RESET && !dq_sync)begin done<=1;error<=2;end
     else begin busy<=1;drive_low<=1;end
    end
   end else begin
    count<=count+1'b1;
    if(op==RESET)begin
     if(count==500*US-1)drive_low<=0;
     // +2 compensates the two input synchronizer clocks: sample raw DQ at release+70us.
     if(count==570*US+2-1)presence<=!dq_sync;
     if(count==980*US+2-1)stuck<=!dq_sync;
     if(count==1000*US-1)begin busy<=0;done<=1;drive_low<=0;error<=stuck?3'd2:presence?3'd0:3'd1;end
    end else begin
     if(count==(op==READ?2*US:(data?5*US:65*US))-1)drive_low<=0;
     if(op==READ && count==15*US+2-1)read_bit<=dq_sync;
     if(count==75*US-1)begin busy<=0;done<=1;drive_low<=0;end
    end
   end
  end
 `ifndef SYNTHESIS
 initial begin
  if(CLK_HZ<1000000 || CLK_HZ%1000000!=0)$fatal(1,"CLK_HZ must be an integer MHz >=1MHz");
 end
 `endif
endmodule
