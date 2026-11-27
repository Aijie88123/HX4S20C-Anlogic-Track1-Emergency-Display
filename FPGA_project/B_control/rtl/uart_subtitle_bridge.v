// Shared physical UART: legacy ASCII maintenance and bounded binary subtitle blocks.
// Host frame: ESC,S,1 + 28 little-endian packet bytes + CRC16-CCITT(low,high).
// Reply: ESC,A,1,tag,op,indexLo,indexHi,status + CRC16(low,high).
module uart_subtitle_bridge #(parameter CLK_HZ=25000000,BAUD=115200,
 RETRY_CYCLES=625000,TIMEOUT_CYCLES=50000000,CHAR_TIMEOUT=25000000)(
 input clk,rst,uart_rx,output uart_tx,input online,
 output legacy_rx_valid,output [7:0] legacy_rx_data,output legacy_rx_error,
 input legacy_idle,legacy_tx_valid,input [7:0] legacy_tx_data,output legacy_tx_ready,
 output stream_valid,output [223:0] stream_data,input stream_ready,
 input packet_valid,input [223:0] packet);
 wire rxv,rxe,txready;wire [7:0] rxd;wire txvalid;wire [7:0] txdata;
 maintenance_uart #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) phy(.clk(clk),.rst(rst),.rx(uart_rx),.tx(uart_tx),
 .rx_valid(rxv),.rx_data(rxd),.rx_error(rxe),.tx_valid(txvalid),.tx_data(txdata),.tx_ready(txready));
 function [15:0] crc_byte;input [15:0] c;input [7:0] v;reg [15:0] t;integer k;begin
 t=c^{v,8'd0};for(k=0;k<8;k=k+1)t=t[15]?(t<<1)^16'h1021:t<<1;crc_byte=t;end endfunction
 reg [2:0] rxstate;reg [5:0] rxindex;reg [223:0] shift,held;reg [15:0] crc;reg [7:0] crc_low;
 reg blocked,net_wait,send_pending;reg [25:0] total_age;reg [24:0] retry_age,char_age;
 reg reply_wait,reply_active;reg [3:0] txindex;reg [15:0] txcrc;
 reg [7:0] reply_tag,reply_op,reply_status;reg [15:0] reply_index;
 assign legacy_rx_valid=rxv&&rxstate==0&&rxd!=8'h1b&&!net_wait&&!reply_wait&&!reply_active;
 assign legacy_rx_data=rxd;assign legacy_rx_error=rxe&&rxstate==0;
 assign legacy_tx_ready=txready&&!reply_active;
 assign stream_valid=net_wait&&send_pending&&online;assign stream_data=held;
 wire ack=packet_valid&&packet[7:0]==19&&packet[15:8]==1&&packet[223:192]==32'h53554231&&
 packet[31:24]==held[31:24]&&packet[55:48]==held[23:16]&&packet[47:32]==held[47:32];
 reg [7:0] rb;
 always @*case(txindex)
 0:rb=8'h1b;1:rb="A";2:rb=1;3:rb=reply_tag;4:rb=reply_op;5:rb=reply_index[7:0];6:rb=reply_index[15:8];7:rb=reply_status;
 8:rb=txcrc[7:0];default:rb=txcrc[15:8];endcase
 assign txvalid=reply_active?1'b1:legacy_tx_valid;
 assign txdata=reply_active?rb:legacy_tx_data;
 task respond;input [7:0] status,tag,op;input [15:0] idx;begin
 reply_wait<=1;reply_status<=status;reply_tag<=tag;reply_op<=op;reply_index<=idx;end endtask
 always @(posedge clk or posedge rst)
 if(rst)begin rxstate<=0;rxindex<=0;shift<=0;held<=0;crc<=16'hffff;crc_low<=0;blocked<=0;net_wait<=0;send_pending<=0;
 total_age<=0;retry_age<=0;char_age<=0;reply_wait<=0;reply_active<=0;txindex<=0;txcrc<=16'hffff;reply_tag<=0;reply_op<=0;reply_index<=0;reply_status<=0;end
 else begin
  if(rxstate!=0&&char_age<CHAR_TIMEOUT)char_age<=char_age+1'b1;
  if(rxstate!=0&&char_age==CHAR_TIMEOUT-1)begin rxstate<=0;if(!net_wait&&!reply_wait&&!reply_active)respond(6,0,0,0);end
  if(reply_wait&&legacy_idle&&txready&&!legacy_tx_valid&&!reply_active)begin reply_wait<=0;reply_active<=1;txindex<=0;txcrc<=16'hffff;end
  if(reply_active&&txready)begin
   if(txindex<8)txcrc<=crc_byte(txcrc,rb);
   if(txindex==9)begin reply_active<=0;txindex<=0;end else txindex<=txindex+1'b1;
  end
  if(stream_valid&&stream_ready)begin send_pending<=0;retry_age<=0;end
  if(net_wait)begin
   total_age<=total_age+1'b1;
   if(retry_age<RETRY_CYCLES-1)retry_age<=retry_age+1'b1;
   else begin send_pending<=1;retry_age<=0;end
   if(!online||total_age==TIMEOUT_CYCLES-1)begin net_wait<=0;send_pending<=0;respond(online?8'd5:8'd3,held[31:24],held[23:16],held[47:32]);end
   else if(ack)begin net_wait<=0;send_pending<=0;respond(packet[23:16],held[31:24],held[23:16],held[47:32]);end
  end
  if(rxe&&rxstate!=0)begin rxstate<=0;if(!net_wait&&!reply_wait&&!reply_active)respond(2,0,0,0);end
  else if(rxv)begin
   char_age<=0;
   case(rxstate)
    0:if(rxd==8'h1b)begin rxstate<=1;blocked<=!legacy_idle||net_wait||reply_wait||reply_active;end
    1:if(rxd=="S")rxstate<=2;else begin rxstate<=4;end
    2:if(rxd==1)begin rxstate<=3;rxindex<=0;crc<=16'hffff;end else rxstate<=4;
    3:begin
     if(rxindex<28)begin shift<={rxd,shift[223:8]};crc<=crc_byte(crc,rxd);end
     else if(rxindex==28)crc_low<=rxd;
     if(rxindex==29)begin
      rxstate<=0;
      if(blocked||net_wait||reply_wait||reply_active)begin if(!net_wait&&!reply_wait&&!reply_active)respond(4,shift[31:24],shift[23:16],shift[47:32]);end
      else if({rxd,crc_low}!=crc)respond(2,shift[31:24],shift[23:16],shift[47:32]);
      else if(shift[7:0]!=18||shift[15:8]!=1||shift[223:192]!=32'h53554231||shift[23:16]>3)respond(6,shift[31:24],shift[23:16],shift[47:32]);
      else if(!online)respond(3,shift[31:24],shift[23:16],shift[47:32]);
      else begin held<=shift;net_wait<=1;send_pending<=1;total_age<=0;retry_age<=0;end
     end else rxindex<=rxindex+1'b1;
    end
    4:if(rxd==10)begin rxstate<=0;if(!net_wait&&!reply_wait&&!reply_active)respond(6,0,0,0);end
   endcase
  end
 end
endmodule
