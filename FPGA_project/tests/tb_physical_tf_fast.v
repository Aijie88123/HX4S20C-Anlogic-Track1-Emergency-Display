`timescale 1ns/1ps
module tb_physical_tf_fast #(parameter FAST_MODE=0);
 wire ready,valid,last;
 reg sdclk=0,bclk=0,net=0,rst=1,online=1;
 always #5 sdclk=~sdclk;always #10 bclk=~bclk;always #20 net=~net;
 reg fast_delivery=0;
 integer clock_ticks=0,last_tick=0,fast_bytes=0,slow_bytes=0,midbyte_changes=0;
 reg previous_fast=0;
 always @(negedge bclk)begin
  if(FAST_MODE==0)fast_delivery=0;
  else if(FAST_MODE==1)fast_delivery=1;
  else fast_delivery=clock_ticks[4]^clock_ticks[6];
 end
 always @(posedge bclk)begin
  clock_ticks=clock_ticks+1;
  #1;
  if(!rst && client.sd_state==3 && client.emit_phase!=0 && fast_delivery!=client.byte_fast)
   midbyte_changes=midbyte_changes+1;
  if(valid)begin
   if(client.emit_index!=0 && clock_ticks-last_tick!=(previous_fast?8:32))
    $fatal(1,"FAIL: byte pacing mode=%d index=%d delta=%d expected=%d",FAST_MODE,client.emit_index,clock_ticks-last_tick,previous_fast?8:32);
   last_tick=clock_ticks;previous_fast=client.byte_fast;
   if(client.byte_fast)fast_bytes=fast_bytes+1;else slow_bytes=slow_bytes+1;
  end
 end
 reg req=0;reg [31:0] lba=0;wire [7:0] data;
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
 wire ncs,sck,mosi,miso;
 a_tf_sector_service #(.RETRY_CYCLES(2000)) server(.sd_clk(sdclk),.net_clk(net),.rst(rst),.online(online),
  .packet_valid(filtered_a),.packet(received_a),.stream_valid(av),.stream_data(ap),.stream_ready(ar),
  .sd_miso(miso),.sd_ncs(ncs),.sd_dclk(sck),.sd_mosi(mosi));
 card_spi_physical_tf card(.rst(rst),.ncs(ncs),.sck(sck),.mosi(mosi),.miso(miso));
 remote_sd_sector_bridge #(.QUERY_CYCLES(25000),.ENABLE_FAST_DELIVERY(1)) client(.fast_delivery(fast_delivery),.sd_clk(bclk),.net_clk(net),.rst(rst),.online(online),
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
 ethernet_frame_tx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(8)) atx(
  .clk(net),.rst(rst),.start(astart),.message(21'd0),.extension(8'd0),.stream_data(asend),.busy(ab),.nibble(an));
 ethernet_frame_tx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(8)) btx(
  .clk(net),.rst(rst),.start(bstart),.message(21'd0),.extension(8'd0),.stream_data(bsend),.busy(bb),.nibble(bn));
 ethernet_frame_rx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(8)) arx(
  .clk(net),.rst(rst),.nibble(bn),.valid(bb),.error(1'b0),.packet_valid(pa),.message(),.extension(),.stream_data(received_a));
 ethernet_frame_rx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(8)) brx(
  .clk(net),.rst(rst),.nibble(an),.valid(ab),.error(1'b0),.packet_valid(pb),.message(),.extension(),.stream_data(received_b));
 reg checking=0,expect_failure=0;reg [31:0] expected_lba=0;reg [7:0] expected;
 integer total_bytes=0,good_sectors=0,failed_sectors=0;
 always @(negedge bclk)begin
  if(valid)begin
   if(!checking||n>=512)$fatal(1,"FAIL: unexpected/duplicate parser byte");
   expected=card.card_byte(expected_lba,n);
   if(data!==expected)$fatal(1,"FAIL: byte %d LBA %d actual=%h expected=%h",n,expected_lba,data,expected);
   n=n+1;total_bytes=total_bytes+1;
  end
  if(last)begin
   if(!checking || n!=(expect_failure?0:512))$fatal(1,"FAIL: sector n=%d expect_failure=%b",n,expect_failure);
   if(expect_failure)failed_sectors=failed_sectors+1;else good_sectors=good_sectors+1;
   done=done+1;checking=0;
  end
 end
 task read_sector(input [31:0] address);
  integer previous;
  begin wait(ready);@(negedge bclk);n=0;expected_lba=address;checking=1;previous=done;lba=address;req=1;
   wait(done!=previous);@(negedge bclk);req=0;repeat(10)@(negedge net);end
 endtask
 // Check the real physical SCK, not an internal byte-boundary surrogate.
 integer idle_clocks=0,slow_periods=0,fast_periods=0;
 reg [63:0] previous_rise=0,cold_start=0;
 reg previous_ready=0;
 reg cold_checked=0;
 always @(posedge net)if(!rst && !cold_checked && card.commands!=0)begin
  if(cold_start<100000000||idle_clocks<88)$fatal(1,"FAIL: first CMD0 arrived without the real 100ms wait and 88 idle clocks");
  cold_checked=1;
 end
 always @(posedge sck)if(!rst)begin
  if(cold_start==0)cold_start=$time;
  if(ncs && server.sd_card_top_m0.spi_master_m0.clk_edge_cnt!=0)begin
   if(!mosi)$fatal(1,"FAIL: MOSI low during CS-high cold clocks");
   idle_clocks=idle_clocks+1;
  end
  if(previous_rise!=0)begin
   if(!server.sd_ready && !previous_ready)begin
    if($time-previous_rise<5000)$fatal(1,"FAIL: SD initialization SCK exceeded 200kHz");
    if($time-previous_rise==5000)slow_periods=slow_periods+1;
   end else if(server.sd_ready && previous_ready)begin
    if($time-previous_rise<80)$fatal(1,"FAIL: SD transfer SCK exceeded 12.5MHz");
    if($time-previous_rise==80)fast_periods=fast_periods+1;
   end
  end
  previous_rise=$time;previous_ready=server.sd_ready;
 end
 always @(posedge sdclk)if(!rst && server.sd_ready)
  if(server.sd_card_top_m0.spi_clk_div!==16'd2)$fatal(1,"FAIL: A physical TF divider differs from verified DIV=2");
 initial begin
  repeat(10)@(negedge net);rst=0;
  read_sector(0);read_sector(1);read_sector(3);read_sector(4);read_sector(8);read_sector(12);read_sector(20);
  repeat(3000)@(negedge net);
  if(good_sectors!=7||retries!=3)$fatal(1,"FAIL: sector/ACK retry coverage");
  if(!cold_checked||cold_start<100000000||idle_clocks<88||slow_periods<70||fast_periods<4000)
   $fatal(1,"FAIL: physical power-up/clock coverage t=%d idle=%d slow=%d fast=%d",cold_start,idle_clocks,slow_periods,fast_periods);
  // A real R1 error must close the read, suppress incomplete parser data and let a following read recover.
  @(negedge net);card.reject_cmd17_once=1;expect_failure=1;
  read_sector(5);expect_failure=0;
  read_sector(5);
  // A missing 0xFE token must time out, report an empty failed sector, then recover.
  @(negedge net);card.omit_token_once=1;expect_failure=1;
  read_sector(6);expect_failure=0;
  read_sector(6);
  repeat(500)@(negedge net);
  if(good_sectors!=9||failed_sectors!=2||total_bytes!=4608||card.rejected_reads!=1||card.missing_tokens!=1||card.delayed_responses<96)
   $fatal(1,"FAIL: recovery coverage good=%d fail=%d bytes=%d rejected=%d missing=%d",good_sectors,failed_sectors,total_bytes,card.rejected_reads,card.missing_tokens);
  $display("PASS: real spi_master pins (22ns MISO) + 100ms cold wait + 88 idle clocks + 200kHz init/12.5MHz transfer + actual SD command/sector FSM + A sector service + v8 Ethernet CRC/IFG + B remote bridge; nine complete sectors/4608 exact bytes, delayed R1/token, first/middle/final ACK loss, CMD17 R1 error and missing-token timeout recover with zero partial parser bytes");
  $display("TRACE: good=%0d failed=%0d first_sck_ns=%0d idle_clocks=%0d slow_periods=%0d fast_periods=%0d packets=%0d commands=%0d",good_sectors,failed_sectors,cold_start,idle_clocks,slow_periods,fast_periods,packets,card.commands);
  if(FAST_MODE==0 && fast_bytes!=0)$fatal(1,"FAIL: conservative mode accelerated");
  if(FAST_MODE==1 && (fast_bytes!=4608||slow_bytes!=0))$fatal(1,"FAIL: fast mode coverage");
  if(FAST_MODE==2 && (fast_bytes==0||slow_bytes==0||midbyte_changes==0))$fatal(1,"FAIL: changing pacing coverage");
  $display("PASS: adaptive byte pacing mode=%0d fast=%0d conservative=%0d midbyte_changes=%0d; exact CRC-checked sector bytes, no duplication/partial publication",FAST_MODE,fast_bytes,slow_bytes,midbyte_changes);
  $finish;
 end
 initial begin #1000000000;$fatal(1,"FAIL: real TF timeout A=%d B=%d ready=%b byte=%d sd=%d",server.state,client.state,ready,n,server.sd_state);end
endmodule
