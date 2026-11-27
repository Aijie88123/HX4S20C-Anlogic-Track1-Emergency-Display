module ethernet_pll(input refclk,reset,output clk0_out,clk1_out,clk2_out,extlock);
 reg divider=0;reg run_clock=0,locked_value=0;
 always @(posedge refclk)divider<=~divider;
 assign clk0_out=run_clock ? divider : 1'b0;
 assign clk1_out=clk0_out;assign clk2_out=1'b0;assign extlock=locked_value;
endmodule

module ethernet_command_link #(parameter BOARD_B=0,EXTENDED=0,STREAM=0,MAP=0,MEDIA=0,RASTER=0,RAW_TF=0,RAW_TF_VERSION=12,BURST_RASTER=1,SUBTITLE=0)(
 input clk,tx_clk90,rst,input [2:0] local_state,input [7:0] local_sequence,input local_command_active,input [7:0] local_extension,
 input eth_rx_clk,eth_rx_ctl,input [3:0] eth_rxd,
 output eth_tx_clk,eth_tx_ctl,output [3:0] eth_txd,output eth_mdc,inout eth_mdio,
 output peer_valid,output [20:0] peer_message,output [7:0] peer_extension,output peer_online,phy_configured,phy_link,tx_active,
 input stream_valid,input [223:0] stream_data,output stream_ready,output [223:0] peer_stream);
 reg online_value=0,configured_value=0;reg [20:0] peer_value=0;reg [7:0] feedback_value=0;
 assign stream_ready=1;assign peer_stream=0;
 assign peer_extension=feedback_value;assign peer_message=peer_value;assign peer_online=online_value;
 assign phy_configured=configured_value;assign peer_valid=0;assign phy_link=online_value;
 assign tx_active=0;assign eth_tx_clk=tx_clk90;assign eth_tx_ctl=0;assign eth_txd=0;
 assign eth_mdc=0;assign eth_mdio=1'bz;
endmodule
