`timescale 1ns/1ps
module tb_remote_tf_recovery;
 reg sdclk=0,bclk=0,net=0,rst=1,online=1,b_hold=0,inject_query=0;
 always #5 sdclk=~sdclk;always #10 bclk=~bclk;always #20 net=~net;
 reg req=0;reg [31:0] lba=0;wire ready,valid,last;wire [7:0] data;
 wire av,bv,ar,br,ab,bb;wire [223:0] ap,bp,received_a,received_b;wire [3:0] an,bn;wire pa,pb;
 reg [4:0] agap=0,bgap=0;reg [223:0] asend,bsend;reg astart,bstart;
 reg drop_first=1,drop_middle=1,drop_final=1,drop_data=0;
 integer n=0,done=0,packets=0,drops=0,implicit_handoffs=0,request_overlaps=0,data_drops=0,result_query_overlaps=0;
 wire filtered_a=pa&&!(received_a[7:0]==11&&
  ((received_a[31:24]==0&&drop_first)||(received_a[31:24]==15&&drop_middle)||(received_a[31:24]==31&&drop_final)));
 wire filtered_b=pb&&!(received_b[7:0]==10&&received_b[31:24]==0&&drop_data);
 always @(posedge net)begin
  if(pa&&received_a[7:0]==11)begin
   if(received_a[31:24]==0&&drop_first)begin drop_first<=0;drops<=drops+1;end
   if(received_a[31:24]==15&&drop_middle)begin drop_middle<=0;drops<=drops+1;end
   if(received_a[31:24]==31&&drop_final)begin drop_final<=0;drops<=drops+1;end
  end
  if(pb&&received_b[7:0]==10&&received_b[31:24]==0&&drop_data)begin drop_data<=0;data_drops<=data_drops+1;end
  if(filtered_a&&received_a[7:0]==9&&received_a[31:24]==1&&received_a[23:8]!=server.id&&
     server.block==31&&(server.state==4||server.state==3))implicit_handoffs<=implicit_handoffs+1;
  if(client.request_net&&client.state==4&&client.final_ack&&b_hold)request_overlaps<=request_overlaps+1;
  if(inject_query&&server.result_net&&server.state==1)result_query_overlaps<=result_query_overlaps+1;
 end
 // 2 ms retries exceed the actual 327 us parser publication time. The old
 // 80 us test accidentally repaired a lost final ACK before the next LBA.
 a_tf_sector_service #(.SD_CLK_HZ(1000000),.RETRY_CYCLES(50000)) server(.sd_clk(sdclk),.net_clk(net),.rst(rst),.online(online),
  .packet_valid(filtered_a||inject_query),.packet(inject_query?224'd9:received_a),.stream_valid(av),.stream_data(ap),.stream_ready(ar),
  .sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi());
 remote_sd_sector_bridge #(.RETRY_CYCLES(50000),.QUERY_CYCLES(300)) client(.sd_clk(bclk),.net_clk(net),.rst(rst),.online(online),
  .sd_sec_read(req),.sd_sec_read_addr(lba),.sd_init_done(ready),.sd_sec_read_data(data),.sd_sec_read_data_valid(valid),.sd_sec_read_end(last),
  .packet_valid(filtered_b),.packet(received_b),.stream_valid(bv),.stream_data(bp),.stream_ready(br));
 assign ar=!ab&&agap==0;assign br=!bb&&bgap==0&&!b_hold;
 always @*begin astart=av&&ar;bstart=bv&&br;asend=ap;bsend=bp;end
 always @(posedge net)begin
  if(rst)begin agap<=0;bgap<=0;end
  else begin if(ab)agap<=24;else if(agap!=0)agap<=agap-1'b1;
   if(bb)bgap<=24;else if(bgap!=0)bgap<=bgap-1'b1;end
  if(astart)packets<=packets+1;
 end
 ethernet_frame_tx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1)) atx(
  .clk(net),.rst(rst),.start(astart),.message(21'd0),.extension(8'd0),.stream_data(asend),.busy(ab),.nibble(an));
 ethernet_frame_tx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1)) btx(
  .clk(net),.rst(rst),.start(bstart),.message(21'd0),.extension(8'd0),.stream_data(bsend),.busy(bb),.nibble(bn));
 ethernet_frame_rx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1)) arx(
  .clk(net),.rst(rst),.nibble(bn),.valid(bb),.error(1'b0),.packet_valid(pa),.message(),.extension(),.stream_data(received_a));
 ethernet_frame_rx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1)) brx(
  .clk(net),.rst(rst),.nibble(an),.valid(ab),.error(1'b0),.packet_valid(pb),.message(),.extension(),.stream_data(received_b));
 reg checking=0;reg [31:0] expected_lba=0;reg [7:0] expected;
 always @(negedge bclk)begin
  if(valid)begin
   if(!checking||n>=512)$fatal(1,"FAIL: unexpected/duplicate parser byte");
   expected=server.sd_card_top_m0.spi_master_m0.disk[expected_lba*512+n];if(^expected===1'bx)expected=0;
   if(data!==expected)$fatal(1,"FAIL: byte %d LBA %d actual=%h expected=%h",n,expected_lba,data,expected);
   n=n+1;
  end
  if(last)begin if(!checking||n!=512)$fatal(1,"FAIL: partial sector published n=%d",n);done=done+1;checking=0;end
 end
 task read_sector(input [31:0] address);
  integer previous;
  begin wait(ready);@(negedge bclk);n=0;expected_lba=address;checking=1;previous=done;lba=address;req=1;
   wait(done!=previous);@(negedge bclk);req=0;repeat(10)@(negedge net);end
 endtask
 integer previous;
 initial begin
  repeat(10)@(negedge net);rst=0;
  // The next read follows the parser's real END, well before a 2 ms retry.
  read_sector(0);read_sector(1);read_sector(514);
  if(implicit_handoffs==0||drops!=3)$fatal(1,"FAIL: lost final ACK/new LBA was not covered");
  // Do not request a new LBA until an old final block has been retransmitted.
  // Stall its ACK and deliver the one-clock request mailbox pulse in ACK.
  drop_final=1;read_sector(516);b_hold=1;
  wait(client.state==4&&client.final_ack);
  @(negedge bclk);n=0;expected_lba=514;checking=1;previous=done;lba=514;req=1;
  wait(client.pending_request);repeat(400)@(negedge net);
  if(client.state!=4||n!=0||request_overlaps!=1)$fatal(1,"FAIL: request/old-tail ACK overlap not held");
  b_hold=0;wait(done!=previous);@(negedge bclk);req=0;repeat(10)@(negedge net);
  // Drop the first response: duplicate transaction requests and timeout
  // retransmits must never publish two sectors or alter the 512-byte result.
  drop_data=1;read_sector(1);
  // Partial disconnect discards incomplete sector data and all queued work.
  @(negedge bclk);lba=516;req=1;@(negedge bclk);req=0;
  wait(client.expected_block==10);@(negedge net);online=0;
  repeat(300)@(negedge net);if(ready||valid||last||client.pending_request||server.pending_read)$fatal(1,"FAIL: partial/offline sector");
  online=1;read_sector(516);
  // A client-only reset queries A and cancels the previous transfer first.
  @(negedge bclk);lba=514;req=1;@(negedge bclk);req=0;wait(client.expected_block==8);
  force client.reset=1;repeat(10)@(negedge net);release client.reset;
  read_sector(0);
  // A physical-read result and a restarted B's query can arrive in the same
  // A net-clock. Inject only this exact state-machine timing corner; all
  // sector payloads and normal requests above/below use the real v7 MACs.
  @(negedge bclk);lba=516;req=1;@(negedge bclk);req=0;wait(server.sd_state==1);
  force client.reset=1;wait(server.result_net);@(negedge net);inject_query=1;
  @(negedge net);inject_query=0;repeat(100)@(negedge net);
  if(server.sd_state!=0||result_query_overlaps!=1)$fatal(1,"FAIL: same-clock result/query retained SD ownership");
  release client.reset;read_sector(1);repeat(60000)@(negedge net);
  if(done!=9||drops!=4||data_drops!=1||request_overlaps!=1)$fatal(1,"FAIL: incomplete recovery coverage");
  $display("PASS: protocol-v7 sector recovery with real 327us parser publication and 2ms retries; lost first/middle/final ACK, immediate next LBA handoff=%0d, old-tail retransmit/new-request/ACK backpressure overlap=%0d, data loss/duplicate transaction, partial disconnect, client-only reset and same-clock result/query=%0d; complete sectors=%0d exact bytes=%0d packets=%0d",implicit_handoffs,request_overlaps,result_query_overlaps,done,done*512,packets);
  $finish;
 end
 initial begin #100000000;$fatal(1,"FAIL: remote TF timeout A=%d B=%d ready=%b byte=%d sd=%d pending=%b/%b",server.state,client.state,ready,n,server.sd_state,server.pending_read,client.pending_request);end
endmodule
