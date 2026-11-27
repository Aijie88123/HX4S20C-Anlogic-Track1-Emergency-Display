// Passive diagnostics only. These outputs never feed the Ethernet state machine.
// RX_CTL activity is sampled on the local clock: this is an activity indication,
// not a byte/CRC-qualified frame counter. packet_valid counts accepted MAC frames.
module ethernet_link_diagnostics(
 input clk,rst,configured,link_100,online,tx_active,rx_ctl,packet_valid,
 output [4:0] flags,output [19:0] counts);
 reg [2:0] rx_sync;
 reg tx_d,rx_seen;
 reg [7:0] tx_count,rx_activity_count;
 reg [3:0] good_count;
 assign flags={configured,link_100,online,tx_count!=0,rx_seen};
 assign counts={tx_count,rx_activity_count,good_count};
 always @(posedge clk or posedge rst)
  if(rst)begin rx_sync<=0;tx_d<=0;rx_seen<=0;tx_count<=0;rx_activity_count<=0;good_count<=0;end
  else begin
   rx_sync<={rx_sync[1:0],rx_ctl};tx_d<=tx_active;
   if(tx_active && !tx_d && tx_count!=255)tx_count<=tx_count+1'b1;
   if(rx_sync[1])rx_seen<=1;
   if(rx_sync[1] && !rx_sync[2] && rx_activity_count!=255)rx_activity_count<=rx_activity_count+1'b1;
   if(packet_valid && good_count!=15)good_count<=good_count+1'b1;
  end
endmodule
