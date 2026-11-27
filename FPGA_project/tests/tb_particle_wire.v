`timescale 1ns/1ps
module tb_particle_wire;
 reg clk=0,video_clk=0,rst=1,online=1,enabled=1;
 always #20 clk=~clk;
 always #7 video_clk=~video_clk;
 wire bv,br,bready,av,ar,ap,bp,busy_a,busy_b;
 wire [223:0] bd,ad,received_a,received_b;wire [20:0] ma,mb;wire [7:0] ea,eb;
 wire [3:0] na,nb;reg [4:0] gap_a=0,gap_b=0;
 reg [31:0] cycles=0;reg dropped_ack=0,corrupted_data=0;integer acknowledgements=0,retries=0;
 wire drop_ack=av && ad[31:16]==3 && !dropped_ack;
 wire inject_error=busy_b && tx_b.position==60 && tx_b.held_stream[31:16]==11 && !corrupted_data;
 wire [3:0] nb_wire=inject_error?(nb^4'd1):nb;
 // Foreground service periodically owns the stream slot; the atlas yields.
 wire foreground=cycles[5:0]<12;
 assign br=!busy_b && gap_b==0 && !foreground;
 assign ar=!busy_a && gap_a==0 && !foreground;
 always @(posedge clk)begin
  cycles<=cycles+1;
  if(busy_a)gap_a<=24;else if(gap_a!=0)gap_a<=gap_a-1'b1;
  if(busy_b)gap_b<=24;else if(gap_b!=0)gap_b<=gap_b-1'b1;
  if(drop_ack && ar)dropped_ack<=1;
  if(inject_error)corrupted_data<=1;
  if(av && ar)acknowledgements<=acknowledgements+1;
  if(bv && br && bd[31:16]==3)retries<=retries+1;
 end
 particle_atlas_sender #(.RETRY_CYCLES(1500)) sender(.clk(clk),.rst(rst),.online(online),.enabled(enabled),
  .packet_valid(bp),.packet(received_b),.stream_valid(bv),.stream_data(bd),.stream_ready(br),.ready(bready));
 wire [7:0] code;wire ready;reg [12:0] address=0;
 particle_atlas_receiver receiver(.net_clk(clk),.rst(rst),.online(online),.packet_valid(ap),.packet(received_a),
  .ack_valid(av),.ack_packet(ad),.ack_ready(ar),.video_clk(video_clk),.read_address(address),.read_code(code),.ready(ready));
 ethernet_frame_tx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(9)) tx_b(
 .clk(clk),.rst(rst),.start(!busy_b&&gap_b==0&&(foreground||bv)),.message(21'd0),.extension(8'd0),.stream_data(foreground?224'd2:bd),.busy(busy_b),.nibble(nb));
 ethernet_frame_tx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(9)) tx_a(
 .clk(clk),.rst(rst),.start(!busy_a&&gap_a==0&&(foreground||(av&&!drop_ack))),.message(21'd0),.extension(8'd0),.stream_data(foreground?224'd1:ad),.busy(busy_a),.nibble(na));
 ethernet_frame_rx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(9)) rx_a(
  .clk(clk),.rst(rst),.nibble(nb_wire),.valid(busy_b),.error(1'b0),.packet_valid(ap),.message(ma),.extension(ea),.stream_data(received_a));
 ethernet_frame_rx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(9)) rx_b(
  .clk(clk),.rst(rst),.nibble(na),.valid(busy_a),.error(1'b0),.packet_valid(bp),.message(mb),.extension(eb),.stream_data(received_b));
 reg [7:0] reference[0:8191];integer i;integer packets=0;
 always @(posedge clk)if(ap)begin
  packets<=packets+1;
  if(received_a[7:0]!=2 && (received_a[7:0]!=12 || received_a[15:8]!=1))$fatal(1,"bad accepted particle header");
 end
 initial begin
  $readmemh("particle_reference.hex",reference);
  repeat(12)@(negedge clk);rst=0;
  wait(receiver.next_index==70);@(negedge clk);online=0;
  repeat(80)@(negedge clk);
  if(ready || receiver.next_index!=0)$fatal(1,"partial atlas published or not discarded");
  online=1;
  wait(bready && ready);repeat(4)@(negedge video_clk);
  if(!dropped_ack || !corrupted_data || retries<2)$fatal(1,"loss coverage missing");
  for(i=0;i<8192;i=i+1)begin
   address=i;@(negedge video_clk);@(negedge video_clk);
   if(code!==reference[i])$fatal(1,"atlas mismatch address=%0d got=%h expected=%h",i,code,reference[i]);
  end
  online=0;repeat(80)@(negedge clk);
  if(!ready)$fatal(1,"complete atlas lost on link-only outage");
  online=1;wait(bready);repeat(8)@(negedge clk);
  for(i=0;i<8192;i=i+1)begin
   address=i;repeat(2)@(negedge video_clk);
   if(code!==reference[i])$fatal(1,"duplicate upload overwrote immutable atlas");
  end
  $display("PASS: 8192 independent texels, real v9 MAC/FCS, CRC error, lost ACK/retry, foreground backpressure, mid-upload disconnect and immutable reconnect packets=%0d",packets);
  $finish;
 end
 initial begin #100000000;$fatal(1,"particle wire timeout index=%d state=%d ready=%b",sender.index,sender.state,ready);end
endmodule
