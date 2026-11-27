`timescale 1ns/1ps
// Passive physical-pin card derived from card_spi_pin_model. Real SPI RTL remains present.
// Every command delays R1 eight poll bytes, every read delays its token four bytes.
// The 22 ns MISO delay is a stress value, not a measured board value.
module card_spi_physical_tf(input rst,ncs,sck,mosi,output reg miso=1);
integer bitpos=0,cmd_bytes=0,cmd_id=0,response=0,payload_left=0,read_pos=-2;
integer sectors=0,commands=0;
integer response_polls=0,token_polls=0;
integer delayed_responses=0,rejected_reads=0,missing_tokens=0;
reg reject_cmd17_once=0,omit_token_once=0;
reg [31:0] argument=0,sector=0;
reg [7:0] rx=0,reply=8'hff;
reg accept_command=0;
function [7:0] card_byte;
 input integer lba,index;
 integer image,offset,p,xx,ch,e;
 reg [23:0] color;
 begin
  card_byte=0;
  if(lba==0)begin if(index==450)card_byte=8'h0b;if(index==454)card_byte=1;end
  else if(lba==1)begin
   if(index==13||index==14||index==16||index==36)card_byte=1;
   if(index==44)card_byte=2;
  end else if(lba==3 && index<160)begin
   image=index/32;e=index%32;
   if(e<8)card_byte="A"+image;
   if(e==8)card_byte="B";if(e==9)card_byte="M";if(e==10)card_byte="P";
   if(e==11)card_byte=8'h20;
   if(e==26)card_byte=3+image*4;
   if(e>=28&&e<=31)card_byte=1974>>(8*(e-28));
  end else if(lba>=4 && lba<24)begin
   // Compact 640x1 images still produce a complete 640x480 output frame.
   image=(lba-4)/4;offset=((lba-4)%4)*512+index;
   if(offset==0)card_byte="B";else if(offset==1)card_byte="M";
   else if(offset>=2&&offset<=5)card_byte=1974>>(8*(offset-2));
   else if(offset==10)card_byte=54;
   else if(offset==14)card_byte=40;
   else if(offset>=18&&offset<=21)card_byte=640>>(8*(offset-18));
   else if(offset==22)card_byte=1;
   else if(offset==26)card_byte=1;else if(offset==28)card_byte=24;
   else if(offset>=54&&offset<1974)begin
    p=offset-54;xx=p/3;ch=p%3;
    color={image[7:0],xx[7:0],(xx[7:0]^image[7:0])};
    card_byte=color>>(8*ch);
   end
  end
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
