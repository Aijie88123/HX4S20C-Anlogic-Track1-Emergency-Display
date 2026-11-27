`timescale 1ns/1ps
module tb_mesh3d_wire;
 reg clk=0,render_clk=0,rst=1,online=1,release_toggle=0;
 always #20 clk=~clk;always #10 render_clk=~render_clk;
 reg [223:0] reference[0:353];reg [8:0] source_index=0;
 wire source_valid=online && source_index<354;wire source_ready;
 wire av,ar,bv,br,ap,bp,busy_a,busy_b,mesh_valid;wire [223:0] ad,bd,ra,rb;
 wire [3:0] na,nb;wire [20:0] ma,mb;wire [7:0] ea,eb,count;wire [15:0] id;wire [12:0] meta;
 reg [10:0] address=0;wire [15:0] data;
 reg [4:0] gap_a=0,gap_b=0;reg [31:0] cycles=0;
 reg lost_last_ack=0,corrupted=0;integer retries=0;
 wire foreground=cycles[5:0]<12;
 wire drop_ack=bv && bd[31:16]==1 && bd[39:32]==117 && !lost_last_ack;
 wire inject_error=busy_a && tx_a.position==60 && tx_a.held_stream[7:0]==14 && tx_a.held_stream[39:32]==11 && !corrupted;
 assign ar=!busy_a&&gap_a==0&&!foreground;assign br=!busy_b&&gap_b==0&&!foreground;
 always @(posedge clk)begin
  cycles<=cycles+1;
  if(busy_a)gap_a<=24;else if(gap_a!=0)gap_a<=gap_a-1'b1;
  if(busy_b)gap_b<=24;else if(gap_b!=0)gap_b<=gap_b-1'b1;
  if(!online)source_index<=0;else if(source_valid&&source_ready)source_index<=source_index+1'b1;
  if(drop_ack&&br)lost_last_ack<=1;
  if(inject_error)corrupted<=1;
  if(av&&ar&&ad[39:32]==11)retries<=retries+1;
 end
 mesh3d_packet_sender #(.RETRY_CYCLES(1500)) sender(.clk(clk),.rst(rst),.online(online),
  .triangle_valid(source_valid),.triangle(reference[source_index]),.triangle_ready(source_ready),.packet_valid(ap),.packet(ra),
  .stream_valid(av),.stream_data(ad),.stream_ready(ar));
 mesh3d_packet_receiver receiver(.net_clk(clk),.render_clk(render_clk),.rst(rst),.online(online),.packet_valid(bp),.packet(rb),
  .ack_valid(bv),.ack_packet(bd),.ack_ready(br),.read_address(address),.read_data(data),
  .mesh_valid(mesh_valid),.mesh_count(count),.mesh_id(id),.mesh_meta(meta),.release_toggle(release_toggle));
 ethernet_frame_tx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(10)) tx_a(
  .clk(clk),.rst(rst),.start(!busy_a&&gap_a==0&&(foreground||av)),.message(21'd0),.extension(8'd0),.stream_data(foreground?224'd1:ad),.busy(busy_a),.nibble(na));
 ethernet_frame_tx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(10)) tx_b(
  .clk(clk),.rst(rst),.start(!busy_b&&gap_b==0&&(foreground||(bv&&!drop_ack))),.message(21'd0),.extension(8'd0),.stream_data(foreground?224'd2:bd),.busy(busy_b),.nibble(nb));
 ethernet_frame_rx #(.BOARD_B(0),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(10)) rx_a(
  .clk(clk),.rst(rst),.nibble(nb),.valid(busy_b),.error(1'b0),.packet_valid(ap),.message(ma),.extension(ea),.stream_data(ra));
 ethernet_frame_rx #(.BOARD_B(1),.EXTENDED(1),.STREAM(1),.MAP(1),.MEDIA(1),.RASTER(1),.RAW_TF(1),.RAW_TF_VERSION(10)) rx_b(
  .clk(clk),.rst(rst),.nibble(inject_error?na^4'd1:na),.valid(busy_a),.error(1'b0),.packet_valid(bp),.message(mb),.extension(eb),.stream_data(rb));
 integer frame,i,j;
 initial begin
  $readmemh("mesh3d_projected.hex",reference);repeat(12)@(negedge clk);rst=0;
  wait(receiver.next_index==45);@(negedge clk);online=0;repeat(80)@(negedge clk);
  if(mesh_valid || receiver.next_index!=0)$fatal(1,"FAIL: partial geometry exposed after disconnect");
  online=1;
  for(frame=0;frame<3;frame=frame+1)begin
   wait(mesh_valid && id==frame+1);
   if(count!=118)$fatal(1,"FAIL: count %0d",count);
   for(i=0;i<118;i=i+1)for(j=0;j<14;j=j+1)begin
    address=i*16+j;repeat(2)@(negedge render_clk);
    if(data!==((reference[frame*118+i]>>(j*16))&16'hffff))$fatal(1,"FAIL: geometry frame=%0d triangle=%0d word=%0d data=%h",frame,i,j,data);
   end
   repeat(100)@(negedge clk);
   if(!mesh_valid || id!=frame+1)$fatal(1,"FAIL: immutable geometry overwritten before release");
   @(negedge render_clk);release_toggle=~release_toggle;
  end
  wait(source_index==354);online=0;repeat(80)@(negedge clk);
  if(mesh_valid)$fatal(1,"FAIL: stale 3D geometry kept valid offline");
  if(!lost_last_ack || !corrupted || retries<4)$fatal(1,"FAIL: required CRC/retry coverage missing");
  $display("PASS: 354 real v10 MAC/FCS triangles, 4956 geometry words, CRC rejection/retry, lost final ACK, background priority, partial-scene disconnect/restart, immutable until renderer release and next-scene backpressure");$finish;
 end
 initial begin #100000000;$fatal(1,"FAIL: mesh wire timeout source=%0d rx=%0d available=%b sender=%0d",source_index,receiver.next_index,mesh_valid,sender.state);end
endmodule
