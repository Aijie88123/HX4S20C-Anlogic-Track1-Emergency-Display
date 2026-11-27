`timescale 1ns/1ps
module tb_remote_tf;
 reg sdclk=0,bclk=0,net=0,rst=1,online=1;
 always #5 sdclk=~sdclk;always #10 bclk=~bclk;always #20 net=~net;
 reg req=0;reg [31:0] lba=0;wire ready,valid,last;wire [7:0] data;
 wire av,bv,ar,br,ab,bb;wire [223:0] ap,bp,received_a,received_b;wire [3:0] an,bn;wire pa,pb;
 reg [4:0] agap=0,bgap=0;reg [223:0] asend,bsend;reg astart,bstart;
 reg drop_first=1,drop_middle=1,drop_final=1;integer n=0,done=0,packets=0,retries=0,duplicates=0;
 wire filtered_a=pa&&!(received_a[7:0]==11&&
   ((received_a[31:24]==0&&drop_first)||(received_a[31:24]==15&&drop_middle)||(received_a[31:24]==31&&drop_final)));
 always @(posedge net)begin
  if(pa&&received_a[7:0]==11)begin
   if(received_a[31:24]==0&&drop_first)begin drop_first<=0;retries<=retries+1;end
   if(received_a[31:24]==15&&drop_middle)begin drop_middle<=0;retries<=retries+1;end
   if(received_a[31:24]==31&&drop_final)begin drop_final<=0;retries<=retries+1;end
  end
 end
 a_tf_sector_service #(.SD_CLK_HZ(1000000),.RETRY_CYCLES(2000)) server(.sd_clk(sdclk),.net_clk(net),.rst(rst),.online(online),
  .packet_valid(filtered_a),.packet(received_a),.stream_valid(av),.stream_data(ap),.stream_ready(ar),
  .sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi());
 remote_sd_sector_bridge #(.RETRY_CYCLES(2000),.QUERY_CYCLES(300)) client(.sd_clk(bclk),.net_clk(net),.rst(rst),.online(online),
  .sd_sec_read(req),.sd_sec_read_addr(lba),.sd_init_done(ready),.sd_sec_read_data(data),.sd_sec_read_data_valid(valid),.sd_sec_read_end(last),
  .packet_valid(pb),.packet(received_b),.stream_valid(bv),.stream_data(bp),.stream_ready(br));
 assign ar=!ab&&agap==0;assign br=!bb&&bgap==0;
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
 initial begin
  repeat(10)@(negedge net);rst=0;
  read_sector(0);read_sector(1);read_sector(514);
  // No second parser publication after losing the final ACK.
  repeat(3000)@(negedge net);if(done!=3||retries!=3)$fatal(1,"FAIL: ACK retry coverage");
  wait(ready);@(negedge bclk);lba=516;req=1;@(negedge bclk);req=0;
  wait(client.expected_block==10);@(negedge net);online=0;
  repeat(300)@(negedge net);if(ready||valid||last)$fatal(1,"FAIL: partial/offline sector");
  online=1;read_sector(516);
  // Client-only reset: startup query releases an older A sector first.
  @(negedge bclk);lba=514;req=1;@(negedge bclk);req=0;wait(client.expected_block==8);
  force client.reset=1;repeat(10)@(negedge net);release client.reset;
  read_sector(0);
  $display("PASS: TF stays on A: real SPI command reader -> protocol-v7 Ethernet CRC/IFG -> B verified 512-byte sectors; first/middle/final ACK loss, no duplicate parser bytes, partial disconnect discard/reconnect and client restart resynchronization; sectors=%0d packets=%0d",done,packets);$finish;
 end
 initial begin #30000000;$fatal(1,"FAIL: remote TF timeout A=%d B=%d ready=%b byte=%d sd=%d",server.state,client.state,ready,n,server.sd_state);end
endmodule
