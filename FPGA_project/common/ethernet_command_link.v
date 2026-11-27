// Two-board state/ACK heartbeat over 100M Ethernet, no video packets/IP stack.
module ethernet_command_link #(
 parameter BOARD_B=0,EXTENDED=0,STREAM=0,MAP=0,MEDIA=0,RASTER=0,RAW_TF=0,RAW_TF_VERSION=7,BURST_RASTER=0,HEARTBEAT_CYCLES=2500000,BOOT_CYCLES=1048576,TIMEOUT_TICKS=10,SUBTITLE=0
)(input clk,tx_clk90,rst,input [2:0] local_state,input [7:0] local_sequence,input local_command_active,input [7:0] local_extension,
 input eth_rx_clk,eth_rx_ctl,input [3:0] eth_rxd,
 output eth_tx_clk,eth_tx_ctl,output [3:0] eth_txd,output eth_mdc,inout eth_mdio,
 output peer_valid,output [20:0] peer_message,output [7:0] peer_extension,output peer_online,phy_configured,phy_link,
 output tx_active,
 input stream_valid,input [223:0] stream_data,output stream_ready,output [223:0] peer_stream);
 reg [21:0] heartbeat_count;wire heartbeat=(heartbeat_count==HEARTBEAT_CYCLES-1);
 always @(posedge clk or posedge rst)
  if(rst)heartbeat_count<=0;
  else if(heartbeat)heartbeat_count<=0;
  else heartbeat_count<=heartbeat_count+1'b1;
 wire [2:0] phy_address;
 ethernet_phy_config #(.BOOT_CYCLES(BOOT_CYCLES)) phy(
  .clk(clk),.rst(rst),.poll(heartbeat),.mdio(eth_mdio),.mdc(eth_mdc),
  .configured(phy_configured),.link_100_full(phy_link),.address(phy_address));
 wire [3:0] rx_nibble;wire rx_dv,rx_ctl_fall;wire rx_error=rx_dv^rx_ctl_fall;
 wire rx_rst=rst || !phy_configured;
 genvar k;
 generate for(k=0;k<4;k=k+1)begin:rx_io
  EG_LOGIC_IDDR #(.ASYNCRST("ENABLE"),.PIPEMODE("PIPED")) iddr(
   .q0(rx_nibble[k]),.q1(),.clk(eth_rx_clk),.d(eth_rxd[k]),.rst(rx_rst));
 end endgenerate
 EG_LOGIC_IDDR #(.ASYNCRST("ENABLE"),.PIPEMODE("PIPED")) rx_control(
  .q0(rx_dv),.q1(rx_ctl_fall),.clk(eth_rx_clk),.d(eth_rx_ctl),.rst(rx_rst));
 wire [223:0] rx_stream;
 wire rx_packet;wire [20:0] rx_message;wire [7:0] rx_extension;wire mailbox_ready;
 generate if(BURST_RASTER && !BOARD_B)begin: burst_receiver
  ethernet_raster_burst_rx #(.VERSION(RAW_TF_VERSION)) receiver(
   .clk(eth_rx_clk),.rst(rx_rst),.nibble(rx_nibble),.valid(rx_dv),.error(rx_error),.output_ready(mailbox_ready),
   .packet_valid(rx_packet),.message(rx_message),.extension(rx_extension),.stream_data(rx_stream));
 end else begin: legacy_receiver
 ethernet_frame_rx #(.BOARD_B(BOARD_B),.EXTENDED(EXTENDED),.STREAM(STREAM),.MAP(MAP),.MEDIA(MEDIA),.RASTER(RASTER),.RAW_TF(RAW_TF),.RAW_TF_VERSION(RAW_TF_VERSION),.SUBTITLE(SUBTITLE)) receiver(
  .clk(eth_rx_clk),.rst(rx_rst),.nibble(rx_nibble),.valid(rx_dv),.error(rx_error),
  .packet_valid(rx_packet),.message(rx_message),.extension(rx_extension),.stream_data(rx_stream));
 end endgenerate
 localparam RX_BITS=RAW_TF?224:(BOARD_B?128:224);
 wire [RX_BITS+28:0] rx_bundle;
 assign rx_bundle={rx_stream[RX_BITS-1:0],rx_extension,rx_message};
 wire [RX_BITS-1:0] delivered_stream;
 assign peer_stream=STREAM?{{(224-RX_BITS){1'b0}},delivered_stream}:224'd0;
 ethernet_mailbox #(.WIDTH(STREAM?RX_BITS+29:(EXTENDED?29:21))) receive_mailbox(
  .src_clk(eth_rx_clk),.src_rst(rst),.src_valid(rx_packet),.src_data(STREAM?rx_bundle:(EXTENDED?{rx_extension,rx_message}:rx_message)),.src_ready(mailbox_ready),
  .dst_clk(clk),.dst_rst(rst),.dst_valid(peer_valid),.dst_data({delivered_stream,peer_extension,peer_message}));
 reg ack_valid;reg [7:0] ack_sequence;reg [3:0] age;
 always @(posedge clk or posedge rst)
  if(rst)begin ack_valid<=0;ack_sequence<=0;age<=TIMEOUT_TICKS;end
  else if(peer_valid)begin ack_valid<=1;ack_sequence<=peer_message[10:3];age<=0;end
  else if(heartbeat && age<TIMEOUT_TICKS)age<=age+1'b1;
 assign peer_online=phy_configured && phy_link && ack_valid && age<TIMEOUT_TICKS;
 wire [20:0] outgoing={local_command_active,ack_valid,ack_sequence,local_sequence,local_state};
 wire [3:0] tx_nibble;
 // Changes request an immediate packet; periodic heartbeats retry lost phases.
 reg [7:0] previous_extension,previous_sequence;reg urgent_pending;
 wire changed=EXTENDED && ((previous_extension!=local_extension)||(previous_sequence!=local_sequence));
 // All frames obey a 12-byte (24-nibble) interframe gap. Control is
 // scheduled ahead of PCM/results, including heartbeats that arrived busy.
 reg [4:0] gap_count;
 reg heartbeat_pending;
 wire control_pending=heartbeat || heartbeat_pending || urgent_pending || changed;
 wire may_start=phy_link && !tx_active && gap_count==0;
 wire burst_ready,burst_control_sent;
 assign stream_ready=BURST_RASTER && BOARD_B?burst_ready:STREAM && may_start && !control_pending;
 wire send_stream=STREAM && stream_valid && stream_ready;
 wire tx_start=may_start && (control_pending || send_stream);
 wire control_launch=BURST_RASTER && BOARD_B?burst_control_sent:tx_start && !send_stream;
 always @(posedge clk or posedge rst)
  if(rst)begin gap_count<=0;heartbeat_pending<=0;end
  else begin
   if(tx_active)gap_count<=24;else if(gap_count!=0)gap_count<=gap_count-1'b1;
   if(heartbeat)heartbeat_pending<=1;
   else if(control_launch)heartbeat_pending<=0;
  end
 always @(posedge clk or posedge rst)
  if(rst)begin previous_extension<=0;previous_sequence<=0;urgent_pending<=0;end
  else begin
   previous_extension<=EXTENDED?local_extension:8'd0;previous_sequence<=local_sequence;
   if(changed)urgent_pending<=1;else if(control_launch)urgent_pending<=0;
  end
 generate if(BURST_RASTER && BOARD_B)begin: burst_transmitter
  ethernet_raster_burst_tx #(.VERSION(RAW_TF_VERSION)) transmitter(
   .clk(clk),.rst(rst),.online(phy_link),.may_start(may_start),.control_pending(control_pending),
   .message(outgoing),.extension(local_extension),.stream_valid(stream_valid),.stream_data(stream_data),
   .stream_ready(burst_ready),.control_sent(burst_control_sent),.busy(tx_active),.nibble(tx_nibble));
 end else begin: legacy_transmitter
  assign burst_ready=0;assign burst_control_sent=0;
 ethernet_frame_tx #(.BOARD_B(BOARD_B),.EXTENDED(EXTENDED),.STREAM(STREAM),.MAP(MAP),.MEDIA(MEDIA),.RASTER(RASTER),.RAW_TF(RAW_TF),.RAW_TF_VERSION(RAW_TF_VERSION)) transmitter(
  .clk(clk),.rst(rst),.start(tx_start),.message(outgoing),.extension(local_extension),.stream_data(send_stream?stream_data:224'd0),.busy(tx_active),.nibble(tx_nibble));
 end endgenerate
 generate for(k=0;k<4;k=k+1)begin:tx_io
  EG_LOGIC_ODDR #(.ASYNCRST("ENABLE")) oddr(
   .q(eth_txd[k]),.clk(clk),.d0(tx_nibble[k]),.d1(tx_nibble[k]),.rst(rst));
 end endgenerate
 EG_LOGIC_ODDR #(.ASYNCRST("ENABLE")) tx_control(
  .q(eth_tx_ctl),.clk(clk),.d0(tx_active),.d1(tx_active),.rst(rst));
 EG_LOGIC_ODDR #(.ASYNCRST("ENABLE")) tx_clock(
  .q(eth_tx_clk),.clk(tx_clk90),.d0(1'b1),.d1(1'b0),.rst(rst));
endmodule
