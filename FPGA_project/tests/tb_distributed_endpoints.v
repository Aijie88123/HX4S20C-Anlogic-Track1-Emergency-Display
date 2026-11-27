`timescale 1ns/1ps
module tb_distributed_endpoints #(parameter RX_DELAY=2);
 reg a_clk=0,b_clk=0,video_clk=0,a90=0,b90=0;
 always #20 a_clk=~a_clk;
 initial begin #3;forever #20 b_clk=~b_clk;end
 initial begin #10;forever #20 a90=~a90;end
 initial begin #13;forever #20 b90=~b90;end
 always #6.667 video_clk=~video_clk;
 reg rst=1,connected=1,local_toggle=0,local_step=0;
 reg b_armed=0;reg [2:0] b_state=0;reg [7:0] b_seq=0;
 wire a_txclk,b_txclk,a_txctl,b_txctl;wire [3:0] a_data,b_data;
 wire #(RX_DELAY) a_rxclk=b_clk;wire #(RX_DELAY) b_rxclk=a_clk;
 wire a_valid,b_valid,a_online,b_online,a_config,b_config,a_link,b_link;
 wire [7:0] a_extension,b_extension;reg [7:0] a_feedback=8'h1e,b_phase=8'h22;
 wire [20:0] a_peer,b_peer;wire a_mdc,b_mdc;tri1 a_mdio,b_mdio;
 wire a_ready,b_ready;wire [2:0] a_state;wire mode;wire [1:0] event_type;
 wire remote_valid;wire [10:0] remote_command;wire [2:0] status_net;wire status_valid;
 phy_model #(.ADDR(1)) phy_a(.mdc(a_mdc),.mdio(a_mdio),.link_enable(connected),.ready(a_ready));
 phy_model #(.ADDR(3)) phy_b(.mdc(b_mdc),.mdio(b_mdio),.link_enable(connected),.ready(b_ready));
 ethernet_command_link #(.BOARD_B(0),.EXTENDED(1),.BOOT_CYCLES(8),.HEARTBEAT_CYCLES(5000),.TIMEOUT_TICKS(3)) a(
  .clk(a_clk),.tx_clk90(a90),.rst(rst),.local_state(status_net),.local_sequence(8'd0),.local_command_active(1'b0),.local_extension(a_feedback),
  .eth_rx_clk(a_rxclk),.eth_rx_ctl(connected?b_txctl:1'b0),.eth_rxd(b_data),
  .eth_tx_clk(a_txclk),.eth_tx_ctl(a_txctl),.eth_txd(a_data),.eth_mdc(a_mdc),.eth_mdio(a_mdio),
  .peer_valid(a_valid),.peer_message(a_peer),.peer_extension(a_extension),.peer_online(a_online),.phy_configured(a_config),.phy_link(a_link),.tx_active());
 ethernet_command_link #(.BOARD_B(1),.EXTENDED(1),.BOOT_CYCLES(8),.HEARTBEAT_CYCLES(5000),.TIMEOUT_TICKS(3)) b(
  .clk(b_clk),.tx_clk90(b90),.rst(rst),.local_state(b_state),.local_sequence(b_seq),.local_command_active(b_armed),.local_extension(b_phase),
  .eth_rx_clk(b_rxclk),.eth_rx_ctl(connected?a_txctl:1'b0),.eth_rxd(a_data),
  .eth_tx_clk(b_txclk),.eth_tx_ctl(b_txctl),.eth_txd(b_data),.eth_mdc(b_mdc),.eth_mdio(b_mdio),
  .peer_valid(b_valid),.peer_message(b_peer),.peer_extension(b_extension),.peer_online(b_online),.phy_configured(b_config),.phy_link(b_link),.tx_active());
 ethernet_mailbox #(.WIDTH(11)) commands(.src_clk(a_clk),.src_rst(rst),.src_valid(a_valid && a_peer[20]),.src_data(a_peer[10:0]),.src_ready(),
  .dst_clk(video_clk),.dst_rst(rst),.dst_valid(remote_valid),.dst_data(remote_command));
 dual_board_emergency_control control(.clk(video_clk),.rst(rst),.local_toggle(local_toggle),.local_event_step(local_step),
  .remote_valid(remote_valid),.remote_command(remote_command),.emergency_mode(mode),.emergency_event(event_type));
 assign a_state={event_type,mode};
 ethernet_mailbox #(.WIDTH(3)) status(.src_clk(video_clk),.src_rst(rst),.src_valid(1'b1),.src_data(a_state),.src_ready(),
  .dst_clk(a_clk),.dst_rst(rst),.dst_valid(status_valid),.dst_data(status_net));
 wire acknowledged=b_online && b_peer[19] && b_peer[18:11]==b_seq && b_peer[2:0]==b_state;
 integer count_a=0,count_b=0;integer capture;reg [3:0] last_a,last_b;reg ctl_a,ctl_b;reg was_a=0,was_b=0;
 always @(posedge a_txclk)begin
  last_a=a_data;ctl_a=a_txctl;
  if(a_txctl)$fwrite(capture,"%x",a_data);else if(was_a)$fwrite(capture,"\n");
  was_a=a_txctl;
 end
 always @(negedge a_txclk)if(!rst && (a_data!==last_a || a_txctl!==ctl_a))$fatal(1,"FAIL: A 100M repeated nibble");
 always @(posedge b_txclk)begin last_b=b_data;ctl_b=b_txctl;end
 always @(negedge b_txclk)if(!rst && (b_data!==last_b || b_txctl!==ctl_b))$fatal(1,"FAIL: B 100M repeated nibble");
 always @(posedge a_clk)if(a_valid)count_a=count_a+1;
 always @(posedge b_clk)if(b_valid)count_b=count_b+1;
 task send;input [7:0] seq;input [2:0] state;begin @(negedge b_clk);b_seq=seq;b_state=state;b_armed=1;#1;wait(acknowledged);#100;end endtask
 task toggle;begin @(negedge video_clk);local_toggle=1;@(negedge video_clk);local_toggle=0;end endtask
 initial begin
  capture=$fopen("distributed_endpoint_tx_nibbles.hex","w");#300;rst=0;
  wait(a_config && b_config && a_link && b_link && a_online && b_online);
  if(!a_ready || !b_ready || b.phy_address!=3)$fatal(1,"FAIL: PHY discovery/config");
  wait(a_extension==b_phase && b_extension==a_feedback);
  @(negedge b_clk);b_phase=8'h36;
  wait(a_extension==8'h36);
  @(negedge a_clk);a_feedback=8'h07;
  wait(b_extension==8'h07);
  send(1,5);if(!mode || event_type!=2)$fatal(1,"FAIL: remote activation");
  send(2,7);if(!mode || event_type!=3)$fatal(1,"FAIL: remote event");
  connected=0;#1000000;
  if(a_online || b_online || !mode)$fatal(1,"FAIL: disconnect/alarm retention");
  connected=1;wait(a_online && b_online && acknowledged);
  // Rebooted controller publishes only an unarmed normal heartbeat.
  @(negedge b_clk);b_armed=0;b_seq=0;b_state=0;#700000;
  if(!mode || event_type!=3 || acknowledged)$fatal(1,"FAIL: unarmed controller cleared alarm");
  send(2,7);
  toggle;#700000;if(mode || acknowledged)$fatal(1,"FAIL: local cancel/actual-state ACK");
  send(3,3);if(!mode || event_type!=1)$fatal(1,"FAIL: new command after local override");
  send(4,0);if(mode)$fatal(1,"FAIL: remote clear");
  toggle;#700000;if(!mode || acknowledged)$fatal(1,"FAIL: local alarm retention");
  if(count_a<10 || count_b<10)$fatal(1,"FAIL: missing heartbeats");
  $fclose(capture);
  $display("PASS: protocol v2 epoch/phase/ready fields and immediate updates; independent-clock RGMII with vendor DDR models, PHY address 1/3 discovery, MDIO turnaround/RMW, 100M duplex, actual-state ACK, CDC, disconnect/reconnect and local override; packets A=%0d B=%0d",count_a,count_b);$finish;
 end
 initial begin #15000000;$fatal(1,"FAIL: endpoint timeout config=%b%b link=%b%b online=%b%b packets=%0d/%0d",a_config,b_config,a_link,b_link,a_online,b_online,count_a,count_b);end
endmodule
