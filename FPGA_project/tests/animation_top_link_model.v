`timescale 1ns/1ps
module ethernet_pll(input refclk,reset,output reg clk0_out=0,output clk1_out,clk2_out,extlock);
 always #20 clk0_out=~clk0_out;assign clk1_out=clk0_out;assign clk2_out=0;assign extlock=1;
endmodule
// Packet boundary surrogate. The separate v9 concurrency bench exercises MAC/CRC/PHY.
module ethernet_command_link #(
 parameter BOARD_B=0,EXTENDED=0,STREAM=0,MAP=0,MEDIA=0,RASTER=0,RAW_TF=0,RAW_TF_VERSION=7,
 HEARTBEAT_CYCLES=2500000,BOOT_CYCLES=1048576,TIMEOUT_TICKS=10)(
 input clk,tx_clk90,rst,input [2:0] local_state,input [7:0] local_sequence,input local_command_active,input [7:0] local_extension,
 input eth_rx_clk,eth_rx_ctl,input [3:0] eth_rxd,output eth_tx_clk,eth_tx_ctl,output [3:0] eth_txd,output eth_mdc,inout eth_mdio,
 output reg peer_valid=0,output [20:0] peer_message,output [7:0] peer_extension,output peer_online,phy_configured,phy_link,tx_active,
 input stream_valid,input [223:0] stream_data,output stream_ready,output reg [223:0] peer_stream=0);
 reg [7:0] feedback=8'h44;reg emergency=0;
 reg ack_in=0;reg [223:0] ack_data=0;
 assign peer_extension=feedback;assign peer_message={20'd0,emergency};assign peer_online=!rst;
 reg [7:0] spacing=0;
 always @(posedge clk)if(rst)spacing<=0;else if(stream_valid&&stream_ready)spacing<=169;else if(spacing!=0)spacing<=spacing-1'b1;
 assign phy_configured=1;assign phy_link=1;assign tx_active=spacing!=0;assign stream_ready=spacing==0;
 assign eth_tx_clk=clk;assign eth_tx_ctl=0;assign eth_txd=0;assign eth_mdc=0;
 always @(posedge clk)begin peer_valid<=ack_in;peer_stream<=ack_data;end
endmodule
