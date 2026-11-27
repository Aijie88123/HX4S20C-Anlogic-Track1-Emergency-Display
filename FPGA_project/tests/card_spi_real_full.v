`timescale 1ns/1ps
// Byte-boundary card model. sd_card_cmd and sd_card_sec_read_write remain real.
// This full-display component test substitutes physical SPI shifting only.
// Physical SPI+v8 MAC/FCS are separately checked by run_physical_tf_link.py.
// All bytes below come from the six saved real BMP/FAT32 fixture.
module spi_master #(parameter FULL_IMAGES=0)(
 input sys_clk,rst, input CPOL,CPHA,nCS_ctrl,input [15:0] clk_div,
 input wr_req, output reg wr_ack, input [7:0] data_in,output reg [7:0] data_out,
 output nCS,DCLK,MOSI,input MISO);
 assign nCS=nCS_ctrl;assign DCLK=sys_clk;assign MOSI=1'b1;
 reg fail_page3=0;
 reg pause_transport=0;
 reg missing_token=0;
 reg [2:0] phase=0;
 reg [7:0] tx;
 reg tx_cs;
 integer cmd_bytes=0,cmd_id=0,response=0,payload_left=0,read_pos=-2;
 reg [31:0] argument=0,sector=0;
 reg [7:0] reply;
 integer page,off,stride,pos,x,y,lane,entry,j;
 reg [23:0] rgb;
reg [31:0] keys[0:11875];reg [7:0] bytes[0:6080511];integer fd,n,last_lba=-1,last_index=-1;
initial begin
 $readmemh("real_card_vectors/lbas.hex",keys);fd=$fopen("real_card_vectors/sectors.bin","rb");n=$fread(bytes,fd);$fclose(fd);
 if(n!=6080512)$fatal(1,"FAIL: physical captured card bytes");
end
function [7:0] card_byte;
 input integer lba,index;integer lo,hi,mid;
 begin
  if(lba!=last_lba)begin
   lo=0;hi=11875;last_index=-1;
   while(lo<=hi)begin mid=(lo+hi)/2;if(keys[mid]==lba)begin last_index=mid;lo=hi+1;end else if(keys[mid]<lba)lo=mid+1;else hi=mid-1;end
   if(last_index<0)$fatal(1,"FAIL: real SPI requests uncaptured sector %0d",lba);
   last_lba=lba;
  end
  card_byte=bytes[last_index*512+index];
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
   if(rst)begin phase<=0;wr_ack<=0;data_out<=8'hff;cmd_bytes=0;response=0;payload_left=0;read_pos=-2;end
   else if(pause_transport)begin wr_ack<=0;end
   else begin
     wr_ack<=0;
     case(phase)
       0:if(wr_req)begin tx<=data_in;tx_cs<=nCS_ctrl;phase<=1;end
       1:phase<=2;
       2:begin transfer_byte;data_out<=reply;wr_ack<=1;phase<=3;end
       // Match the real shifter's ACK_WAIT before accepting the next byte.
       3:phase<=4;
       4:phase<=0;
     endcase
   end
 end
endmodule
