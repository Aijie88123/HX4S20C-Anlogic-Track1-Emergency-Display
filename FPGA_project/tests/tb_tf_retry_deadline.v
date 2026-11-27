`timescale 1ns/1ps
module tb_tf_retry_deadline #(parameter EXPECT_FAILURE=0);
 localparam MISO_DELAY_NS=22;reg load_start=0,load_abort=0,loading=0;wire load_complete,pixel_valid;wire[3:0] error_code;integer drops_left=0,pixels=0,load_bytes=0;
 wire [15:0] width,height;reg scan_start=0;
 reg sdclk=0,bclk=0,net=0,rst=1,online=1;
 always #5 sdclk=~sdclk;always #10 bclk=~bclk;always #20 net=~net;
 wire req;wire [31:0] lba;wire ready,valid,last;wire [7:0] data;
 wire av,bv,ar,br,ab,bb;wire [223:0] ap,bp,received_a,received_b;wire [3:0] an,bn;wire pa,pb;
 reg [4:0] agap=0,bgap=0;reg [223:0] asend,bsend;reg astart,bstart;
 reg drop_first=0,drop_middle=0,drop_final=0;integer n=0,done=0,packets=0,retries=0,duplicates=0;
 wire filtered_a=pa&&!(loading&&received_a[7:0]==11&&received_a[31:24]==0&&drops_left>0);
 always @(posedge net)if(pa&&loading&&received_a[7:0]==11&&received_a[31:24]==0&&drops_left>0)begin drops_left=drops_left-1;$display("TRACE: suppress ACK0 at=%0t remaining=%0d",$time,drops_left);end
 always @(posedge bclk)if(loading)begin if(pixel_valid)pixels=pixels+1;if(valid)load_bytes=load_bytes+1;end
 always @(posedge net)begin
  if(pa&&received_a[7:0]==11)begin
   if(received_a[31:24]==0&&drop_first)begin drop_first<=0;retries<=retries+1;end
   if(received_a[31:24]==15&&drop_middle)begin drop_middle<=0;retries<=retries+1;end
   if(received_a[31:24]==31&&drop_final)begin drop_final<=0;retries<=retries+1;end
  end
 end
 wire ncs,sck,mosi,miso;
 a_tf_sector_service #(.SPI_HIGH_SPEED_DIV(6)) server(.sd_clk(sdclk),.net_clk(net),.rst(rst),.online(online),
  .packet_valid(filtered_a),.packet(received_a),.stream_valid(av),.stream_data(ap),.stream_ready(ar),
  .sd_miso(miso),.sd_ncs(ncs),.sd_dclk(sck),.sd_mosi(mosi));
 card_spi_real_capture #(.MISO_DELAY_NS(MISO_DELAY_NS)) card(.rst(rst),.ncs(ncs),.sck(sck),.mosi(mosi),.miso(miso));
 remote_sd_sector_bridge #(.QUERY_CYCLES(25000),.ENABLE_FAST_DELIVERY(1)) client(.fast_delivery(1'b0),.sd_clk(bclk),.net_clk(net),.rst(rst),.online(online),
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
 wire found,scan_done,parser_ready;wire [31:0] handle;wire [2:0] role,total;
bmp_read #(.CLK_FREQ_HZ(50000000),.RELIABLE_MEDIA(1),.NUMBERED_SIX(1)) parser(
 .clk(bclk),.rst(rst),.ready(parser_ready),.load_nearly_done(),.scan_start(scan_start),.scan_start_sector(32'd0),.scan_max_sector(32'hffffffff),.scan_target_count(3'd6),
 .scan_done(scan_done),.scan_error_code(error_code),.scan_found_valid(found),.scan_found_sector(handle),.scan_found_slot(role),.scan_found_total(total),.load_start(load_start),.load_abort(load_abort),.load_complete(load_complete),.load_sector(32'd810),
 .sd_init_done(ready),.state_code(),.bmp_width(16'd640),.bmp_height(16'd480),.src_w(width),.src_h(height),.pixel_start(),.write_req(),.write_req_ack(1'b1),
 .sd_sec_read(req),.sd_sec_read_addr(lba),.sd_sec_read_data(data),.sd_sec_read_data_valid(valid),.sd_sec_read_end(last),.bmp_data_wr_en(pixel_valid),.bmp_data());
reg [5:0] mask=0;
always @(posedge bclk)if(!rst&&found)begin mask[role]=1;$display("TRACE: physical real card found role=%0d cluster=%0d",role,handle);end
initial begin
 #1000;rst=0;wait(ready);repeat(20)@(negedge bclk);scan_start=1;@(negedge bclk);scan_start=0;
 wait(scan_done);repeat(20)@(negedge bclk);
 if(mask!=63)$fatal(1,"FAIL: physical real card mask=%b part=%d data=%d",mask,parser.part_lba_0,parser.data_start);
 loading=1;drops_left=3;load_start=1;@(negedge bclk);load_start=0;
 wait(!parser_ready);
 fork
  begin
   wait(parser_ready || pixels>0);
   if(EXPECT_FAILURE)begin
    if(!parser_ready||pixels!=0||load_complete)$fatal(1,"FAIL: expected production200ms retry/500ms watchdog conflict not reproduced");
    $display("PASS: BEFORE actual200ms default TF retry exceeds500ms BMP watchdog after repeated ACK0 loss: parser aborted without completion; generic storage fault2 branch, no image bytes/pixels=%0d",pixels);$finish;
   end else begin
    if(parser_ready&&pixels==0)$fatal(1,"FAIL: repaired retry still abandoned first load header code=%d",error_code);
    wait(last);repeat(5)@(negedge bclk);
    if(drops_left!=0||load_bytes<1024||pixels<1||error_code!=0)$fatal(1,"FAIL repaired recovery coverage drops=%d bytes=%d pixels=%d error=%d",drops_left,load_bytes,pixels,error_code);
    $display("PASS: AFTER actual2ms default TF retry recovers all3 lost ACK0 before BMP deadline; complete header+data sectors=%0d bytes, pixels=%0d, no abort/error",load_bytes,pixels);
    load_abort=1;@(negedge bclk);load_abort=0;wait(parser_ready);$finish;
   end
  end
  begin #800000000;$fatal(1,"FAIL: retry-deadline scenario timeout parser=%d",parser.state);end
 join
end
initial begin #1000000000;$fatal(1,"FAIL: physical real-card timeout server=%d client=%d parser=%d",server.state,client.state,parser.state);end
endmodule
