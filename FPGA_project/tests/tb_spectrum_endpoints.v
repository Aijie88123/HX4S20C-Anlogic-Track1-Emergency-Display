`timescale 1ns/1ps
module tb_spectrum_endpoints #(parameter RX_DELAY=2);
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
 wire [223:0] a_stream_in,b_stream_in,a_stream_out,b_stream_out;
 wire a_stream_valid,b_stream_valid,a_stream_ready,b_stream_ready;
 reg pcm_input_valid=0;reg [23:0] pcm_input=0;
 wire pcm_net_valid,pcm_ready;wire [23:0] pcm_net;
 ethernet_mailbox #(.WIDTH(24)) pcm_cdc(.src_clk(video_clk),.src_rst(rst),.src_valid(pcm_input_valid),
  .src_data(pcm_input),.src_ready(pcm_ready),.dst_clk(a_clk),.dst_rst(rst),.dst_valid(pcm_net_valid),.dst_data(pcm_net));
 distributed_pcm_sender sender(.clk(a_clk),.rst(rst),.online(a_online),
  .sample_valid(pcm_net_valid),.sample(pcm_net),.sample_restart(1'b0),
  .stream_ready(a_stream_ready),.stream_valid(a_stream_valid),.stream_data(a_stream_out));
 wire [31:0] gap_count;
 distributed_spectrum_worker worker(.clk(b_clk),.rst(rst),.online(b_online),.packet_valid(b_valid),.packet(b_stream_in),
  .stream_ready(b_stream_ready),.stream_valid(b_stream_valid),.stream_data(b_stream_out),.gap_count(gap_count));
 wire net_band_valid,net_band_ready,live;wire [19:0] net_band_data,band_data;wire band_valid;
 distributed_spectrum_client #(.LIVE_CYCLES(30000)) client(.clk(a_clk),.rst(rst),.online(a_online),
  .packet_valid(a_valid),.packet(a_stream_in),.band_ready(net_band_ready),.band_valid(net_band_valid),.band_data(net_band_data),.live(live));
 ethernet_mailbox #(.WIDTH(20)) bands(.src_clk(a_clk),.src_rst(rst),.src_valid(net_band_valid),.src_data(net_band_data),.src_ready(net_band_ready),
  .dst_clk(video_clk),.dst_rst(rst),.dst_valid(band_valid),.dst_data(band_data));
 reg [15:0] expected_magnitude[0:11];integer complete_results=0,display_sets=0;
 wire golden_valid;wire [4:0] golden_index;wire [15:0] golden_magnitude;
 audio_fft_reference #(.P_BINS(12),.P_WIN(64)) golden(.clk(video_clk),.rst(rst || !a_online),
  .I_audio(pcm_input),.I_audio_valid(pcm_input_valid),.O_band_valid(golden_valid),.O_band(golden_index),.O_mag(golden_magnitude));
 always @(posedge video_clk)if(golden_valid)expected_magnitude[golden_index]=golden_magnitude;
 always @(posedge a_clk)if(a_valid && a_stream_in[7:0]==2)begin
  for(integer j=0;j<12;j=j+1)if(a_stream_in[32+j*16+:16]!==expected_magnitude[j])
   $fatal(1,"Remote spectrum changed band %0d actual=%0d expected=%0d",j,a_stream_in[32+j*16+:16],expected_magnitude[j]);
  complete_results=complete_results+1;
 end
 always @(posedge video_clk)if(band_valid)begin
  if(band_data[15:0]!==expected_magnitude[band_data[19:16]])$fatal(1,"Returned video-domain band differs");
  if(band_data[19:16]==11)display_sets=display_sets+1;
 end
 // Four exact signed samples arrive at B in their original order.
 reg [23:0] sent_samples[0:6143];integer received_pcm=0,generated_pcm=0;
 always @(posedge b_clk)if(b_valid && b_stream_in[7:0]==1)begin
  for(integer k=0;k<4;k=k+1)begin
   if(b_stream_in[32+k*24+:24]!==sent_samples[received_pcm])$fatal(1,"PCM lost/reordered at %0d",received_pcm);
   received_pcm=received_pcm+1;
  end
 end
 task send_pcm(input integer number,input real frequency);
  integer n;real phase;integer value;
  begin
   for(n=0;n<number;n=n+1)begin
    #20800;@(negedge video_clk);
    phase=6.283185307179586*frequency*generated_pcm/48000.0;
    value=$rtoi(2000000.0*$sin(phase));pcm_input=value;sent_samples[generated_pcm]=value;generated_pcm=generated_pcm+1;
    if(!pcm_ready)$fatal(1,"PCM CDC not ready at normal 48k cadence");
    pcm_input_valid=1;@(negedge video_clk);pcm_input_valid=0;
   end
  end
 endtask
 reg was_gap_a=0,was_gap_b=0;
 integer a_gap=100,b_gap=100;
 always @(posedge a_clk)begin
  if(a_txctl)begin if(!was_gap_a && a_gap<24)$fatal(1,"A Ethernet IFG shorter than 12 bytes");a_gap=0;end else a_gap=a_gap+1;
  was_gap_a=a_txctl;
 end
 always @(posedge b_clk)begin
  if(b_txctl)begin if(!was_gap_b && b_gap<24)$fatal(1,"B Ethernet IFG shorter than 12 bytes");b_gap=0;end else b_gap=b_gap+1;
  was_gap_b=b_txctl;
 end
 wire remote_valid;wire [10:0] remote_command;wire [2:0] status_net;wire status_valid;
 phy_model #(.ADDR(1)) phy_a(.mdc(a_mdc),.mdio(a_mdio),.link_enable(connected),.ready(a_ready));
 phy_model #(.ADDR(3)) phy_b(.mdc(b_mdc),.mdio(b_mdio),.link_enable(connected),.ready(b_ready));
 ethernet_command_link #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.BOOT_CYCLES(8),.HEARTBEAT_CYCLES(5000),.TIMEOUT_TICKS(3)) a(
  .clk(a_clk),.tx_clk90(a90),.rst(rst),.local_state(status_net),.local_sequence(8'd0),.local_command_active(1'b0),.local_extension(a_feedback),
  .eth_rx_clk(a_rxclk),.eth_rx_ctl(connected?b_txctl:1'b0),.eth_rxd(b_data),
  .eth_tx_clk(a_txclk),.eth_tx_ctl(a_txctl),.eth_txd(a_data),.eth_mdc(a_mdc),.eth_mdio(a_mdio),
  .peer_valid(a_valid),.peer_message(a_peer),.peer_extension(a_extension),.peer_online(a_online),.phy_configured(a_config),.phy_link(a_link),.tx_active(),
  .stream_valid(a_stream_valid),.stream_data(a_stream_out),.stream_ready(a_stream_ready),.peer_stream(a_stream_in));
 ethernet_command_link #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.BOOT_CYCLES(8),.HEARTBEAT_CYCLES(5000),.TIMEOUT_TICKS(3)) b(
  .clk(b_clk),.tx_clk90(b90),.rst(rst),.local_state(b_state),.local_sequence(b_seq),.local_command_active(b_armed),.local_extension(b_phase),
  .eth_rx_clk(b_rxclk),.eth_rx_ctl(connected?a_txctl:1'b0),.eth_rxd(a_data),
  .eth_tx_clk(b_txclk),.eth_tx_ctl(b_txctl),.eth_txd(b_data),.eth_mdc(b_mdc),.eth_mdio(b_mdio),
  .peer_valid(b_valid),.peer_message(b_peer),.peer_extension(b_extension),.peer_online(b_online),.phy_configured(b_config),.phy_link(b_link),.tx_active(),
  .stream_valid(b_stream_valid),.stream_data(b_stream_out),.stream_ready(b_stream_ready),.peer_stream(b_stream_in));
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
  capture=$fopen("spectrum_endpoint_tx_nibbles.hex","w");#300;rst=0;
  wait(a_config && b_config && a_link && b_link && a_online && b_online);
  if(!a_ready || !b_ready || b.phy_address!=3)$fatal(1,"FAIL: PHY discovery/config");
  wait(a_extension==b_phase && b_extension==a_feedback);
  @(negedge b_clk);b_phase=8'h36;
  wait(a_extension==8'h36);
  @(negedge a_clk);a_feedback=8'h07;
  wait(b_extension==8'h07);
  fork
   begin
    send_pcm(1536,261.63);
    wait(display_sets==2);
    send_pcm(1536,440.0);
    wait(display_sets==4);
    send_pcm(1536,1200.0);
    wait(display_sets==6);
   end
   begin
    #2000000;send(1,5);if(!mode || event_type!=2)$fatal(1,"Remote emergency starved by PCM");
    #4000000;send(2,7);if(!mode || event_type!=3)$fatal(1,"Event command starved by PCM");
    #4000000;send(3,0);if(mode)$fatal(1,"Clear command starved by PCM");
   end
  join
  if(received_pcm!=generated_pcm || gap_count!=0 || complete_results!=6)$fatal(1,"PCM/result count or continuity failed");
  wait(!live);
  connected=0;#1000000;
  if(a_online || b_online || live)$fatal(1,"Disconnect did not invalidate remote analysis");
  connected=1;wait(a_online && b_online);
  send_pcm(1536,800.0);wait(display_sets==8);
  if(received_pcm!=generated_pcm || complete_results!=8)$fatal(1,"Reconnect failed to restart a complete window");
  send(4,3);if(!mode || event_type!=1)$fatal(1,"Remote command failed after reconnect");
  if(count_a<10 || count_b<10)$fatal(1,"FAIL: missing heartbeats");
  $fclose(capture);
  $display("PASS: v3 real RGMII/MDIO/CRC; 6144 exact signed PCM samples; 8 complete twelve-band sets equal the frozen local analyzer; narrow video CDC; minimum IFG; control priority; stale timeout; disconnect/reconnect; packets A=%0d B=%0d",count_a,count_b);$finish;
 end
 initial begin #220000000;$fatal(1,"FAIL: endpoint timeout config=%b%b link=%b%b online=%b%b packets=%0d/%0d",a_config,b_config,a_link,b_link,a_online,b_online,count_a,count_b);end
endmodule
