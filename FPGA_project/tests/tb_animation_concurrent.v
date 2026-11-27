`timescale 1ns/1ps
// Exact production TX priorities; real command links, PHY config, CRC/IFG,
// mailboxes, PCM sender, spectrum worker, TF endpoints and image endpoints.
// RAM backing this bounded 600-pixel image is modeled; physical SPI byte
// shifting is modeled by card_spi_storage (real-wire SPI has its own test).
module tb_animation_concurrent;
 reg net=0,a90=0,b90=0,sdclk=0,bclk=0,rst=1;
 always #20 net=~net;always #5 sdclk=~sdclk;always #10 bclk=~bclk;
 initial begin #10;forever #20 a90=~a90;end
 initial begin #10;forever #20 b90=~b90;end
 wire #(2) rxclk=net;
 wire a_valid,b_valid,a_online,b_online,a_link,b_link,a_cfg,b_cfg,a_busy,b_busy;
 wire [20:0] a_peer,b_peer;wire [7:0] a_extension,b_extension;
 wire [223:0] a_packet,b_packet,a_out,b_out;
 wire a_ready,b_ready,a_stream,b_stream,a_txctl,b_txctl,a_txclk,b_txclk,a_mdc,b_mdc;
 wire [3:0] a_txd,b_txd;tri1 a_mdio,b_mdio;
 wire image_ack_valid;reg raster_ack_valid=0;
 phy_model #(.ADDR(1)) phy_a(.mdc(a_mdc),.mdio(a_mdio),.link_enable(1'b1),.ready());
 phy_model #(.ADDR(3)) phy_b(.mdc(b_mdc),.mdio(b_mdio),.link_enable(1'b1),.ready());
 reg emergency_map_ready=0;reg animation_request=0;wire [6:0] net_feedback;
 ethernet_mailbox #(.WIDTH(7)) u_feedback(.src_clk(sdclk),.src_rst(rst),.src_valid(1'b1),
  .src_data({animation_request,emergency_map_ready,5'b00110}),.src_ready(),.dst_clk(net),.dst_rst(rst),.dst_valid(),.dst_data(net_feedback));
 reg [1:0] active_sync;
 always @(posedge bclk or posedge rst)
  if(rst)active_sync<=0;else active_sync<={active_sync[0],b_online&&b_peer[0]&&b_extension[5]};
 ethernet_command_link #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(9),.BOOT_CYCLES(8),.HEARTBEAT_CYCLES(25000)) alink(
  .clk(net),.tx_clk90(a90),.rst(rst),.local_state(3'd1),.local_sequence(8'd0),.local_command_active(1'b0),.local_extension({1'd0,net_feedback}),
  .eth_rx_clk(rxclk),.eth_rx_ctl(b_txctl),.eth_rxd(b_txd),.eth_tx_clk(a_txclk),.eth_tx_ctl(a_txctl),.eth_txd(a_txd),.eth_mdc(a_mdc),.eth_mdio(a_mdio),
  .peer_valid(a_valid),.peer_message(a_peer),.peer_extension(a_extension),.peer_online(a_online),.phy_configured(a_cfg),.phy_link(a_link),.tx_active(a_busy),
  .stream_valid(a_stream),.stream_data(a_out),.stream_ready(a_ready),.peer_stream(a_packet));
 ethernet_command_link #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(9),.BOOT_CYCLES(8),.HEARTBEAT_CYCLES(25000)) blink(
  .clk(net),.tx_clk90(b90),.rst(rst),.local_state(3'd1),.local_sequence(8'd0),.local_command_active(1'b0),.local_extension(8'd0),
  .eth_rx_clk(rxclk),.eth_rx_ctl(a_txctl),.eth_rxd(a_txd),.eth_tx_clk(b_txclk),.eth_tx_ctl(b_txctl),.eth_txd(b_txd),.eth_mdc(b_mdc),.eth_mdio(b_mdio),
  .peer_valid(b_valid),.peer_message(b_peer),.peer_extension(b_extension),.peer_online(b_online),.phy_configured(b_cfg),.phy_link(b_link),.tx_active(b_busy),
  .stream_valid(b_stream),.stream_data(b_out),.stream_ready(b_ready),.peer_stream(b_packet));
 reg samples_on=0,sample_valid=0;reg [23:0] sample=0;integer sample_phase=0,generated=0,received_samples=0;
 reg [23:0] expected_samples[0:9999];wire pcm_valid;wire [223:0] pcm_packet;
 always @(posedge net)begin
  sample_valid<=0;
  if(samples_on&&a_online)begin
   sample_phase=sample_phase+48000;
   if(sample_phase>=25000000)begin sample_phase=sample_phase-25000000;sample_valid<=1;sample<=generated*7919;generated=generated+1;end
  end
  if(sample_valid)expected_samples[generated-1]=sample;
 end
 distributed_pcm_sender u_pcm(.clk(net),.rst(rst),.online(a_online),.sample_valid(sample_valid),.sample(sample),.sample_restart(1'b0),
  .stream_ready(a_ready),.stream_valid(pcm_valid),.stream_data(pcm_packet));
 wire spectrum_valid;wire [223:0] spectrum_packet;wire [31:0] gap_count;
 distributed_spectrum_worker u_spectrum(.clk(net),.rst(rst),.online(b_online),.packet_valid(b_valid),.packet(b_packet),
  .stream_ready(b_ready),.stream_valid(spectrum_valid),.stream_data(spectrum_packet),.gap_count(gap_count));
 integer spectrum_sets=0,concurrent_spectrum_sets=0;reg transfers_started=0;
 always @(posedge net)begin
  if(b_valid&&b_packet[7:0]==1)begin
   for(integer k=0;k<4;k=k+1)begin
    if(b_packet[32+k*24+:24]!==expected_samples[received_samples])$fatal(1,"FAIL: concurrent PCM loss/order %0d",received_samples);
    received_samples=received_samples+1;
   end
  end
  if(a_valid&&a_packet[7:0]==2)begin spectrum_sets=spectrum_sets+1;if(transfers_started)concurrent_spectrum_sets=concurrent_spectrum_sets+1;end
 end
 wire tf_a_valid,tf_b_valid;wire [223:0] tf_a_packet,tf_b_packet;
 wire tf_a_ready=a_ready&&!pcm_valid&&!raster_ack_valid&&!image_ack_valid;
 wire tf_b_ready=b_ready&&!spectrum_valid; // ENABLE_RASTER=1 production case.
 reg drop_final=1,b_hold_tf=0;integer final_drops=0,handoffs=0,queued_overlaps=0;
 wire filtered_a=a_valid&&!(a_packet[7:0]==11&&a_packet[31:24]==31&&drop_final);
 always @(posedge net)begin
  if(a_valid&&a_packet[7:0]==11&&a_packet[31:24]==31&&drop_final)begin drop_final<=0;final_drops<=final_drops+1;end
  if(filtered_a&&a_packet[7:0]==9&&a_packet[31:24]==1&&a_packet[23:8]!=server.id&&server.block==31&&(server.state==4||server.state==3))handoffs<=handoffs+1;
  if(client.request_net&&client.state==4&&client.final_ack&&b_hold_tf)queued_overlaps<=queued_overlaps+1;
 end
 a_tf_sector_service #(.SD_CLK_HZ(1000000),.RETRY_CYCLES(50000)) server(.net_clk(net),.sd_clk(sdclk),.rst(rst),.online(a_online),
  .packet_valid(filtered_a),.packet(a_packet),.stream_valid(tf_a_valid),.stream_data(tf_a_packet),.stream_ready(tf_a_ready),.sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi());
 reg sec_req=0;reg [31:0] sec_lba=0;wire sec_ready,sec_valid,sec_end;wire [7:0] sec_data;
 remote_sd_sector_bridge #(.RETRY_CYCLES(50000),.QUERY_CYCLES(300),.ENABLE_FAST_DELIVERY(1)) client(.sd_clk(bclk),.net_clk(net),.rst(rst),.online(b_online),.fast_delivery(1'b1),
  .sd_sec_read(sec_req),.sd_sec_read_addr(sec_lba),.sd_init_done(sec_ready),.sd_sec_read_data(sec_data),.sd_sec_read_data_valid(sec_valid),.sd_sec_read_end(sec_end),
  .packet_valid(b_valid),.packet(b_packet),.stream_valid(tf_b_valid),.stream_data(tf_b_packet),.stream_ready(tf_b_ready&&!b_hold_tf));
 // B image source and A image receiver are real stop-and-wait endpoints.
 reg image_available=0,image_more=0;wire image_valid,image_read_busy,image_read_req,image_read_en;
 wire [223:0] image_packet,image_ack;wire [127:0] media_ack_net=image_ack[127:0];
 wire image_ack_ready=a_ready&&!pcm_valid&&!raster_ack_valid;
 wire image_ready=b_ready&&!spectrum_valid&&!tf_b_valid&&!b_hold_tf;
 reg image_read_ack=0,image_empty=1;reg [31:0] image_read_data=0;integer image_read_index=0,image_writes=0;
 wire [2:0] image_role;wire image_write_req,image_write_en,image_commit;wire [31:0] image_write_data;
 reg image_write_ack=0,image_done_toggle=0;integer image_commits=0;
 media_image_sender #(.FRAME_PIXELS(600),.RETRY_CYCLES(50000),.IMAGE_ROLES(6)) image_sender(.clk(net),.rst(rst),.online(b_online),
  .available(image_available?(image_more?6'b001100:6'b000100):6'd0),.source_sizes({64'd0,32'h01e00280,32'h01e00280,64'd0}),.source_fault(4'd0),.source_fault_recurring(1'b0),
  .packet_valid(b_valid),.packet(b_packet),.stream_valid(image_valid),.stream_data(image_packet),.stream_ready(image_ready),
  .read_busy(image_read_busy),.read_req(image_read_req),.read_ack(image_read_ack),.read_empty(image_empty),.read_data(image_read_data),.read_en(image_read_en),.read_role(image_role));
 media_image_receiver #(.FRAME_PIXELS(600),.IMAGE_ROLES(6)) image_receiver(.clk(net),.rst(rst),.online(a_online),
  .packet_valid(a_valid),.packet(a_packet),.ack_valid(image_ack_valid),.ack_packet(image_ack),.ack_ready(image_ack_ready),
  .write_cancel(),.write_req(image_write_req),.write_ack(image_write_ack),.write_full(1'b0),.write_done_toggle(image_done_toggle),
  .write_en(image_write_en),.write_data(image_write_data),.frame_commit_valid(image_commit),.frame_commit_ready(1'b1),
  .commit_role(),.commit_width(),.commit_height(),.transfer_active(),.remote_fault(),.remote_fault_recurring());
 always @(posedge net)begin
  image_read_ack<=image_read_req;image_write_ack<=image_write_req;
  if(image_read_req&&!image_read_ack)begin image_read_index<=0;image_empty<=0;end
  if(image_read_en&&!image_empty)begin image_read_data<={24'h543210+image_read_index[23:0],8'd0};image_read_index<=image_read_index+1;if(image_read_index==599)image_empty<=1;end
  if(image_write_req&&!image_write_ack)image_writes<=0;
  if(image_write_en)begin
   if(image_write_data!=={24'h543210+image_writes[23:0],8'd0})$fatal(1,"FAIL: concurrent image pixel %0d",image_writes);
   image_writes<=image_writes+1;if(image_writes==599)image_done_toggle<=~image_done_toggle;
  end
  if(image_commit)image_commits<=image_commits+1;
 end
 // A raster ACKs occupy the exact higher-priority production slot, bounding
 // lower-priority TF service under substantial independent business traffic.
 reg [223:0] raster_ack=224'd8;integer raster_timer=0,raster_packets=0;
 wire raster_ack_ready=a_ready&&!pcm_valid;
 always @(posedge net)begin
  if(samples_on)begin
   if(raster_timer==1750)begin raster_timer<=0;raster_ack_valid<=1;end else raster_timer<=raster_timer+1;
   if(raster_ack_valid&&raster_ack_ready)begin raster_ack_valid<=0;raster_packets<=raster_packets+1;end
  end
 end
 assign a_stream=pcm_valid||raster_ack_valid||image_ack_valid||tf_a_valid;
 assign a_out=pcm_valid?pcm_packet:raster_ack_valid?raster_ack:image_ack_valid?{96'd0,media_ack_net}:tf_a_packet;
 // No scene packets when ENABLE_RASTER=1; no map pixel stream is scheduled
 // before feedback bit 5. The real renderer's enable expression is above.
 // The fault injector stalls the lower-priority stream at its MAC boundary.
 // Both valid and ready must be suppressed; an ACK cannot be transmitted
 // while its endpoint is being told that the packet was not accepted.
 assign b_stream=spectrum_valid||(!b_hold_tf&&(tf_b_valid||image_valid));
 assign b_out=spectrum_valid?spectrum_packet:tf_b_valid?tf_b_packet:image_packet;
 reg checking=0;integer sec_n=0,sector_done=0;reg [31:0] expected_lba;reg [7:0] expected_byte;
 always @(negedge bclk)begin
  if(sec_valid)begin
   if(!checking||sec_n>=512)$fatal(1,"FAIL: partial/duplicate concurrent sector byte");
   expected_byte=server.sd_card_top_m0.spi_master_m0.disk[expected_lba*512+sec_n];if(^expected_byte===1'bx)expected_byte=0;
   if(sec_data!==expected_byte)$fatal(1,"FAIL: concurrent sector %0d byte %0d",expected_lba,sec_n);
   sec_n=sec_n+1;
  end
  if(sec_end)begin if(!checking||sec_n!=512)$fatal(1,"FAIL: concurrent END without 512 bytes");sector_done=sector_done+1;checking=0;end
 end
 task read_sector(input [31:0] address);
  integer previous;
  begin wait(sec_ready);@(negedge bclk);sec_n=0;expected_lba=address;checking=1;previous=sector_done;sec_lba=address;sec_req=1;
   wait(sector_done!=previous);@(negedge bclk);sec_req=0;repeat(10)@(negedge net);end
 endtask
 integer previous,fa,fb;reg was_a=0,was_b=0;
 always @(posedge a_txclk)begin if(a_txctl)$fwrite(fa,"%x",a_txd);else if(was_a)$fwrite(fa,"\n");was_a=a_txctl;end
 always @(posedge b_txclk)begin if(b_txctl)$fwrite(fb,"%x",b_txd);else if(was_b)$fwrite(fb,"\n");was_b=b_txctl;end
 initial begin
  fa=$fopen("tf_concurrent_a.hex","w");fb=$fopen("tf_concurrent_b.hex","w");repeat(10)@(negedge net);rst=0;
  wait(a_online&&b_online);samples_on=1;wait(spectrum_sets>=1);transfers_started=1;image_available=1;
  read_sector(0);read_sector(1);
  if(handoffs!=1)$fatal(1,"FAIL: concurrent tail ACK loss/new LBA handoff not covered");
  #2000000;drop_final=1;read_sector(514);b_hold_tf=1;
  wait(client.state==4&&client.final_ack);@(negedge bclk);sec_n=0;expected_lba=516;checking=1;previous=sector_done;sec_lba=516;sec_req=1;
  wait(client.pending_request);repeat(500)@(negedge net);
  if(client.state!=4||queued_overlaps!=1)$fatal(1,"FAIL: concurrent pending request lost in ACK");
  b_hold_tf=0;wait(sector_done!=previous);@(negedge bclk);sec_req=0;repeat(10)@(negedge net);
  #2000000;read_sector(1);#2000000;read_sector(514);
  wait(image_commits==1);wait(concurrent_spectrum_sets>=1);
  if(active_sync[1]||b_extension[5])$fatal(1,"FAIL: renderer enabled before 05/06-ready feedback");
  @(negedge sdclk);animation_request=1;wait(b_extension[6]);
  @(negedge sdclk);emergency_map_ready=1;wait(b_extension[5]);wait(active_sync[1]);
  image_more=1;read_sector(0);wait(image_commits==2);
  #1000000;if(!a_online||!b_online)$fatal(1,"FAIL: bit5 feedback frames rejected/lost online");
  @(negedge sdclk);emergency_map_ready=0;wait(!b_extension[5]);wait(!active_sync[1]);
  #2000000;if(gap_count||received_samples<1200||spectrum_sets<2||image_writes!=600||sector_done!=7||final_drops!=2||queued_overlaps!=1||raster_packets<100)
   $fatal(1,"FAIL: concurrent coverage PCM=%0d gaps=%0d spectra=%0d image=%0d sectors=%0d drops=%0d overlap=%0d raster=%0d",received_samples,gap_count,spectrum_sets,image_writes,sector_done,final_drops,queued_overlaps,raster_packets);
  $display("PASS: production-priority v9 with actual animation feedback bit6 concurrent PHY/MAC/CRC/IFG: 48k PCM samples=%0d spectra=%0d (%0d concurrent), image pixels=%0d in two frames with ACKs and raster ACK packets=%0d, TF sectors=%0d bytes=%0d, lost-final/new-LBA handoff=%0d, final retransmit/request/ACK-backpressure overlap=%0d; actual bit5 control-frame feedback enables/disables renderer after peer receipt only; PCM/image/TF continue while ready=1",received_samples,spectrum_sets,concurrent_spectrum_sets,image_writes*image_commits,raster_packets,sector_done,sector_done*512,handoffs,queued_overlaps);
  // Finish the physical frame currently on each wire before closing capture.
  samples_on=0;wait(!a_txctl&&!b_txctl);@(posedge a_txclk);@(negedge net);
  $fclose(fa);$fclose(fb);$finish;
 end
 initial begin #150000000;$fatal(1,"FAIL: concurrent timeout Aonline=%b Bonline=%b Astate=%0d Bstate=%0d spectra=%0d image=%0d sectors=%0d bit5=%b",a_online,b_online,server.state,client.state,spectrum_sets,image_commits,sector_done,b_extension[5]);end
endmodule
