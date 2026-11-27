`timescale 1ns/1ps
// Only the physical shifter is replaced. Real SD command/sector, FAT/BMP,
// scaler, asynchronous FIFO IP and RAM request/complete paths remain active.
module spi_master #(parameter FULL_IMAGES=0)(
 input sys_clk,rst,CPOL,CPHA,nCS_ctrl,input [15:0] clk_div,
 input wr_req,output reg wr_ack,input [7:0] data_in,output reg [7:0] data_out,
 output nCS,DCLK,MOSI,input MISO);
 assign nCS=nCS_ctrl;assign DCLK=sys_clk;assign MOSI=1;
 reg [7:0] disk[0:8388607];reg [31:0] starts[0:5];
 initial begin
  $readmemh(FULL_IMAGES?"storage_recovery_vectors/full_disk.hex":"storage_recovery_vectors/small_disk.hex",disk);
  $readmemh(FULL_IMAGES?"storage_recovery_vectors/full_starts.hex":"storage_recovery_vectors/small_starts.hex",starts);
 end
 reg hold_init=0,fail_first_scan=0,bad_source_header=0,failed_scan_sector=0;
 reg [2:0] phase=0;reg [7:0] tx,reply;reg tx_cs;
 integer cmd_bytes=0,cmd_id=0,response=0,payload_left=0,payload_index=0,read_pos=-2;
 reg [31:0] argument=0,sector=0;
 integer reads=0;
 task transfer_byte;
  begin
   reply=8'hff;
   if(tx_cs)begin cmd_bytes=0;response=0;payload_left=0;read_pos=-2;end
   else if(response)begin
    reply=(cmd_id==0||cmd_id==8||cmd_id==55||(cmd_id==41&&hold_init))?1:0;
    if(cmd_id==8||cmd_id==58)begin payload_left=4;payload_index=0;end
    if(cmd_id==17)begin
     sector=argument;reads=reads+1;read_pos=-1;
     failed_scan_sector=fail_first_scan&&argument==0;
     if(failed_scan_sector)fail_first_scan=0;
    end
    response=0;
   end else if(payload_left>0)begin
    if(cmd_id==8)case(payload_index)2:reply=1;3:reply=8'haa;default:reply=0;endcase
    else reply=payload_index==0?8'hc0:0;
    payload_index=payload_index+1;payload_left=payload_left-1;
   end else if(read_pos>=-1)begin
    if(read_pos==-1)reply=8'hfe;
    else if(read_pos<512)begin
     reply=disk[sector*512+read_pos];if(^reply===1'bx)reply=0;
     if(failed_scan_sector)reply=0;
     if(bad_source_header&&sector==starts[3]&&read_pos==26)reply=0;
    end
    else reply=8'hff;
    if(read_pos==513)read_pos=-2;else read_pos=read_pos+1;
   end else if(cmd_bytes==0)begin
    if(tx[7:6]==2'b01)begin cmd_id=tx[5:0];cmd_bytes=1;argument=0;end
   end else begin
    if(cmd_bytes<=4)argument={argument[23:0],tx};
    if(cmd_bytes==5)begin cmd_bytes=0;response=1;end else cmd_bytes=cmd_bytes+1;
   end
  end
 endtask
 always @(posedge sys_clk)begin
  if(rst)begin phase<=0;wr_ack<=0;data_out<=8'hff;cmd_bytes=0;response=0;payload_left=0;read_pos=-2;end
  else begin
   wr_ack<=0;
   case(phase)
    0:if(wr_req)begin tx<=data_in;tx_cs<=nCS_ctrl;phase<=1;end
    1:phase<=2;
    2:begin transfer_byte;data_out<=reply;wr_ack<=1;phase<=3;end
    3:phase<=4;
    4:phase<=0;
   endcase
  end
 end
endmodule
