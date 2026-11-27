`timescale 1ns/1ps
// Variable-rate compact BMP card model (640/427/1280 widths).
// Byte-boundary card model. sd_card_cmd and sd_card_sec_read_write remain real.
// This replaces only physical SPI shifting, not FAT/BMP/scaling/control RTL.
module spi_master(
 input sys_clk,rst, input CPOL,CPHA,nCS_ctrl,input [15:0] clk_div,
 input wr_req, output reg wr_ack, input [7:0] data_in,output reg [7:0] data_out,
 output nCS,DCLK,MOSI,input MISO);
 assign nCS=nCS_ctrl;assign DCLK=sys_clk;assign MOSI=1'b1;
 reg fail_page3=0;
 reg bad_alarm=0;
 reg pause_transport=0;
 reg missing_token=0;
 reg [2:0] phase=0;
 integer pace_count=0, pace_limit=0;
 reg slow_page4=0;
 reg slow_page1=0;
 reg [7:0] tx;
 reg tx_cs;
 integer cmd_bytes=0,cmd_id=0,response=0,payload_left=0,read_pos=-2;
 reg [31:0] argument=0,sector=0;
 reg [7:0] reply;
 integer page,off,stride,pos,x,y,lane,entry,j;
 reg [23:0] rgb;
function [7:0] card_byte;
 input integer lba,index;
 integer image,offset,p,xx,ch,e,w,stride,cl;
 reg [23:0] color;
 reg [63:0] filename;
 begin
  card_byte=0;w=640;stride=1920;
  if(lba==0)begin if(index==450)card_byte=8'h0b;if(index==454)card_byte=1;end
  else if(lba==1)begin
   if(index==13||index==14||index==16)card_byte=1;if(index==36)card_byte=2;
   if(index==44)card_byte=2;
  end else if(lba==2 || lba==3)begin
   cl=(lba-2)*128+index/4;image=(cl-30)/16;off=(cl-30)%16;
   w=image==5?427:image==6?800:image==7?1280:640;stride=((w*3+3)/4)*4;
   j=(54+stride+511)/512;
   if(cl==2 || cl==3 || (cl>=30 && image<8 && off==j-1))card_byte=32'h0fffffff>>(8*(index%4));
   else if(cl>=30 && image<8 && off<j-1)card_byte=(cl+1)>>(8*(index%4));
  end else if(lba==4 && index<32)begin
   filename="PREV_BMP";
   if(index<8)card_byte=filename>>(8*(7-index));
   if(index>=8 && index<=10)card_byte=32;if(index==11)card_byte=16;
   if(index==26)card_byte=3;
  end else if(lba==5 && index<256)begin
   image=7-index/32;e=index%32;cl=30+image*16;
   case(image)
    0:filename="05      ";1:filename="06      ";2:filename="01      ";3:filename="02      ";
    4:filename="03      ";5:filename="02INFO  ";6:filename="03INFO  ";default:filename="04INFO  ";
   endcase
   w=(image==5)?427:((image==6)?800:((image==7)?1280:640));stride=((w*3+3)/4)*4;
   if(e<8)card_byte=filename>>(8*(7-e));
   if(e==8)card_byte="B";if(e==9)card_byte="M";if(e==10)card_byte="P";
   if(e==11)card_byte=32;
   if(e==26)card_byte=cl&255;if(e==27)card_byte=cl>>8;
   if(e>=28&&e<=31)card_byte=(54+stride)>>(8*(e-28));
  end else if(lba>=32 && lba<160)begin
   image=(lba-32)/16;offset=((lba-32)%16)*512+index;
   w=(image==5)?427:((image==6)?800:((image==7)?1280:640));stride=((w*3+3)/4)*4;
   if(offset==0)card_byte="B";else if(offset==1)card_byte="M";
   else if(offset>=2&&offset<=5)card_byte=(54+stride)>>(8*(offset-2));
   else if(offset==10)card_byte=54;
   else if(offset==14)card_byte=40;
   else if(offset>=18&&offset<=21)card_byte=w>>(8*(offset-18));
   else if(offset==22)card_byte=1;
   else if(offset==26)card_byte=1;else if(offset==28)card_byte=24;
   else if(offset>=54&&offset<54+w*3)begin
    p=offset-54;xx=p/3;ch=p%3;
    color={8'(image+16),8'(image+67),8'(image+123)};card_byte=color>>(8*ch);
   end
  end
  if(bad_alarm && lba==32 && index==0)card_byte="X";
 end
endfunction
 task transfer_byte;
   begin
     reply=8'hff;
     if(tx_cs)begin cmd_bytes=0;response=0;payload_left=0;read_pos=-2;end
     else if(response)begin
       if(cmd_id==0||cmd_id==8||cmd_id==55)reply=8'h01;else reply=8'h00;
       if(cmd_id==8)payload_left=4;
       if(cmd_id==17)begin
         sector=argument;
         if(fail_page3&&argument==4+3*1801+3)begin reply=8'h04;read_pos=-2;end
         else read_pos=missing_token ? -2 : -1;
       end
       response=0;
     end else if(payload_left>0)begin reply=0;payload_left=payload_left-1;end
     else if(read_pos>=-1)begin
       if(read_pos==-1)reply=8'hfe;
       else if(read_pos<512)reply=card_byte(sector,read_pos);
       else reply=8'hff;
       if(read_pos==513)read_pos=-2;else read_pos=read_pos+1;
     end else if(cmd_bytes==0)begin
       if(tx[7:6]==2'b01)begin cmd_id=tx[5:0];cmd_bytes=1;argument=0;end
     end else begin
       if(cmd_bytes<=4)argument={argument[23:0],tx};
       if(cmd_bytes==5)begin cmd_bytes=0;response=1;end
       else cmd_bytes=cmd_bytes+1;
     end
   end
 endtask
 always @(posedge sys_clk)begin
   if(rst)begin phase<=0;wr_ack<=0;data_out<=8'hff;cmd_bytes=0;response=0;payload_left=0;read_pos=-2;pace_count=0;end
   else if(pause_transport)begin wr_ack<=0;end
   else begin
     wr_ack<=0;
     case(phase)
       0:if(wr_req)begin tx<=data_in;tx_cs<=nCS_ctrl;phase<=1;end
       1:begin
         pace_limit=0;
         if(pace_count>=pace_limit)begin pace_count=0;phase<=2;end
         else pace_count=pace_count+1;
       end
       2:begin transfer_byte;data_out<=reply;wr_ack<=1;phase<=3;end
       // Match the real shifter's ACK_WAIT before accepting the next byte.
       3:phase<=4;
       4:phase<=0;
     endcase
   end
 end
endmodule
