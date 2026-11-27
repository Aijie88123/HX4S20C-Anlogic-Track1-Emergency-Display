`timescale 1ns/1ps
// Passive physical-pin card derived from card_spi_pin_model. Real SPI RTL remains present.
// Every command delays R1 eight poll bytes, every read delays its token four bytes.
// The 22 ns MISO delay is a stress value, not a measured board value.
module card_spi_physical_six(input rst,ncs,sck,mosi,output reg miso=1);
integer bitpos=0,cmd_bytes=0,cmd_id=0,response=0,payload_left=0,read_pos=-2;
integer sectors=0,commands=0;
integer response_polls=0,token_polls=0;
integer delayed_responses=0,rejected_reads=0,missing_tokens=0;
reg reject_cmd17_once=0,omit_token_once=0;
reg [31:0] argument=0,sector=0;
reg [7:0] rx=0,reply=8'hff;
reg accept_command=0;
reg [7:0] disk[0:32434687];
initial $readmemh("six_vectors_small/disk.hex",disk);
function [7:0] card_byte;
 input integer lba,index;
 begin
  card_byte=disk[lba*512+index];
  if(^card_byte===1'bx)card_byte=0;
 end
endfunction
task prepare_reply;
 begin
  reply=8'hff;accept_command=0;
  if(response)begin
   if(response_polls>0)begin response_polls=response_polls-1;delayed_responses=delayed_responses+1;end
   else begin
    if(cmd_id==0||cmd_id==8||cmd_id==55)reply=1;else reply=0;
    if(cmd_id==8)payload_left=4;
    if(cmd_id==17)begin
     sector=argument;sectors=sectors+1;token_polls=4;
     if(reject_cmd17_once)begin reply=8'h04;read_pos=-2;reject_cmd17_once=0;rejected_reads=rejected_reads+1;end
     else if(omit_token_once)begin read_pos=-2;omit_token_once=0;missing_tokens=missing_tokens+1;end
     else read_pos=-1;
    end
    response=0;
   end
  end else if(payload_left>0)begin reply=0;payload_left=payload_left-1;end
  else if(read_pos>=-1)begin
   if(read_pos==-1 && token_polls>0)token_polls=token_polls-1;
   else begin
    if(read_pos==-1)reply=8'hfe;
    else if(read_pos<512)reply=card_byte(sector,read_pos);
    if(read_pos==513)read_pos=-2;else read_pos=read_pos+1;
   end
  end else accept_command=1;
 end
endtask
always @(posedge ncs or posedge rst)begin
 bitpos=0;cmd_bytes=0;response=0;payload_left=0;read_pos=-2;rx=0;miso<=1;
end
always @(negedge sck)if(!rst&&!ncs)begin
 if(bitpos==0)prepare_reply;
 miso <= #22 reply[7-bitpos];
end
always @(posedge sck)if(!rst&&!ncs)begin
 rx={rx[6:0],mosi};
 if(bitpos==7)begin
  if(accept_command)begin
   if(cmd_bytes==0)begin
    if(rx[7:6]==2'b01)begin cmd_id=rx[5:0];cmd_bytes=1;argument=0;end
   end else begin
    if(cmd_bytes<=4)argument={argument[23:0],rx};
    if(cmd_bytes==5)begin
     cmd_bytes=0;response=1;response_polls=8;commands=commands+1;
     if(cmd_id==24)begin $display("FAIL: unexpected card write CMD24");$fatal(1);end
    end else cmd_bytes=cmd_bytes+1;
   end
  end
  bitpos=0;
 end else bitpos=bitpos+1;
end
endmodule
