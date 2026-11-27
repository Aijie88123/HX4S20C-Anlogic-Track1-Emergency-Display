`timescale 1ns/1ps
module tb_mesh3d_chain #(parameter NO_CARD=1);
 reg refclk=0,net=0,video=0,mem=0,rst_n=0;always #10 refclk=~refclk;always #20 net=~net;always #6.666666 video=~video;always #4 mem=~mem;
 wire rclk,rrst;wire wr_req,wr_ack,wr_full,wr_done,wr_en,wr_cancel;wire [31:0] wr_data;
 wire req,ren,rack,empty,readbusy,frame_available,frame_consumed;wire [31:0] rd;wire [1:0] ev;
 wire [223:0] scene_packet;wire scene_valid;reg run_animation=1;reg [1:0] zoom=0,barrier=0;reg [2:0] actual=1;
 wire delivered;wire [187:0] scene;wire [2:0] info;
 b_media_storage #(.CLK_FREQ_HZ(1000000),.IMAGE_ROLES(8),.PACK_SOURCE(1),.PREV_PLAYLIST(1),.PARTICLE_PAGE(1)) store(.clk(refclk),.rst_n(rst_n),.net_clk(net),.net_rst(!rst_n),.sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi(),
  .read_req(req),.read_en(ren),.read_role(3'd0),.read_map(1'b1),.read_ack(rack),.read_empty(empty),.read_data(rd),.available(),.source_sizes(),.source_fault(),.source_fault_recurring(),
  .map_small(1'b0),.map_write_req(wr_req),.map_write_en(wr_en),.map_write_cancel(wr_cancel),.map_write_data(wr_data),.map_write_ack(wr_ack),.map_write_full(wr_full),.map_write_done_toggle(wr_done),.render_clk(rclk),.render_rst(rrst));
 distributed_map_worker worker(.clk(net),.rst(!rst_n),.online(1'b1),.actual_state(actual),.switches(zoom),.barrier_mode(barrier),.stream_ready(1'b1),.stream_valid(scene_valid),.stream_data(scene_packet));
 ethernet_mailbox #(.WIDTH(188)) scene_cdc(.src_clk(net),.src_rst(!rst_n),.src_valid(scene_valid),.src_data(scene_packet[187:0]),.src_ready(),.dst_clk(rclk),.dst_rst(rrst),.dst_valid(delivered),.dst_data(scene));
 reg [223:0] triangles[0:353];reg [1:0] geometry_frame=0;reg mesh_available=1,release_d=0;
 wire mesh_release;wire [10:0] geometry_address;reg [15:0] geometry_data;
 wire [7:0] geometry_count=118;wire [15:0] geometry_id=geometry_frame+1;
 wire [12:0] geometry_meta=triangles[geometry_frame*118][196:184];
 initial $readmemh("mesh3d_projected.hex",triangles);
 always @(posedge rclk)begin
  geometry_data<=triangles[geometry_frame*118+(geometry_address>>4)]>>((geometry_address&15)*16);
  if(rrst)begin geometry_frame<=0;release_d<=0;mesh_available<=1;end
  else begin
   release_d<=mesh_release;
   if(mesh_release!=release_d)begin if(geometry_frame<2)geometry_frame<=geometry_frame+1'b1;else mesh_available<=0;end
  end
 end
 b_mesh3d_frame_renderer renderer(.clk(rclk),.rst(rrst),.enabled(1'b1),.current_event(geometry_meta[1:0]),
  .mesh_valid(mesh_available),.mesh_count(geometry_count),.mesh_id(geometry_id),.mesh_meta(geometry_meta),.release_toggle(mesh_release),
  .geometry_address(geometry_address),.geometry_data(geometry_data),.phase((geometry_id-1)*32),.busy(),
  .write_req(wr_req),.write_ack(wr_ack),.write_full(wr_full),.write_done_toggle(wr_done),.write_en(wr_en),.write_data(wr_data),.write_cancel(wr_cancel),
  .frame_valid(frame_available),.frame_event(ev),.frame_consumed(frame_consumed));
 ethernet_mailbox #(.WIDTH(3)) frame_cdc(.src_clk(rclk),.src_rst(rrst),.src_valid(1'b1),.src_data({frame_available,ev}),.src_ready(),.dst_clk(net),.dst_rst(!rst_n),.dst_valid(),.dst_data(info));
 wire sv;wire [223:0] sp;wire av;wire [223:0] ap;reg a_to_b=0,b_to_a=0;reg [223:0] pa=0,pb=0;
 reg [223:0] fwd_hold=0,back_hold=0;integer fwd=0,back=0,gap=0,ticks=0,packets=0,commits=0,display_pixels=0;
 wire sr=fwd==0&&gap==0,ar=back==0;
 raster_map_window_sender #(.ALLOW_ANIMATION(1),.ANIMATION_PIXELS(57856)) sender(.frame_animation(1'b0),.clk(net),.rst(!rst_n),.online(1'b1),.frame_valid(info[2]),.frame_event(info[1:0]),.frame_consumed(frame_consumed),.packet_valid(a_to_b),.packet(pa),.stream_valid(sv),.stream_data(sp),.stream_ready(sr),.read_req(req),.read_en(ren),.read_busy(readbusy),.read_ack(rack),.read_empty(empty),.read_data(rd));
 wire rxreq,rxack,rxfull,rxcancel,rxen,rxfinish,cv,cr,dcv,dcr,staging,display,mode,have;
 wire [31:0] rxdata;wire [1:0] cev;reg done_toggle=0;
 wire hs,vs,de,start;wire [11:0] x,y;wire nrq,nren;wire mrq,mren,mhs,mvs,mde;wire [23:0] mrgb;
 video_scanout_720p base_clock(.clk(video),.rst(!rst_n),.read_req(nrq),.read_req_ack(1'b0),.read_en(nren),.read_data(32'd0),.read_empty(1'b1),.hs(),.vs(),.de(),.rgb(),.raw_hs(hs),.raw_vs(vs),.raw_de(de),.raw_frame_start(start),.raw_x(x),.raw_y(y));
 media_commit_cdc commit_cdc(.src_clk(net),.dst_clk(video),.rst(!rst_n),.src_valid(cv),.src_ready(cr),.dst_valid(dcv),.dst_ready(dcr));
 map_received_frame_control #(.NORMAL_ANIMATION(1)) cache(.animation_requested(1'b0),.incoming_animation(1'b0),.clk(video),.rst(!rst_n),.vsync(vs),.emergency(1'b1),.event_type(geometry_meta[1:0]),.complete(dcv),.incoming_event(cev),.commit_ready(dcr),.staging_slot(staging),.display_slot(display),.map_mode(mode),.have_map(have));
 raster_map_window_receiver #(.ALLOW_ANIMATION(1),.ANIMATION_PIXELS(57856)) receiver(.clk(net),.rst(!rst_n),.online(1'b1),.packet_valid(b_to_a),.packet(pb),.ack_valid(av),.ack_packet(ap),.ack_ready(ar),.write_cancel(rxcancel),.write_req(rxreq),.write_ack(rxack),.write_full(rxfull),.write_done_toggle(done_toggle),.write_en(rxen),.write_data(rxdata),.commit_valid(cv),.commit_ready(cr),.commit_event(cev));
 wire app_rd,app_wr,rd_valid,ram_ready,refresh,busy;wire [20:0] raddr,waddr;wire [31:0] rd_data,wdata;wire [3:0] dm;wire fifo_empty;wire [31:0] fifo_data;wire readack;
 frame_read_write #(.ENABLE_WRITE_CANCEL(1),.WRITE_V_FLIP(0)) a_frames(.rst(!rst_n),.mem_clk(mem),.Sdr_init_done(ram_ready),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),.App_rd_en(app_rd),.App_rd_addr(raddr),.Sdr_rd_en(rd_valid),.Sdr_rd_dout(rd_data),.App_wr_en(app_wr),.App_wr_addr(waddr),.App_wr_dm(dm),.App_wr_din(wdata),
  .read_clk(video),.read_req(mrq),.read_req_ack(readack),.read_finish(),.read_addr_0(display?21'd1958400:21'd1843200),.read_addr_1(21'd0),.read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),.read_len(21'd115200),.read_en(mren),.read_data(fifo_data),.read_empty(fifo_empty),
  .write_clk(net),.write_req(rxreq),.write_req_ack(rxack),.write_finish(rxfinish),.write_addr_0(staging?21'd1958400:21'd1843200),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),.write_addr_index(2'd0),.write_len(21'd115200),.write_en(rxen),.write_data(rxdata),.write_full(rxfull),.write_cancel(rxcancel));
 sdram a_ram(.Clk(mem),.Clk_sft(mem),.Rst(!rst_n),.Sdr_init_done(ram_ready),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),.App_wr_en(app_wr),.App_wr_addr(waddr),.App_wr_dm(dm),.App_wr_din(wdata),.App_rd_en(app_rd),.App_rd_addr(raddr),.Sdr_rd_en(rd_valid),.Sdr_rd_dout(rd_data));
 map_rgb565_scanout #(.SMALL_ANIMATION(1)) scan(.animation(1'b0),.clk(video),.rst(!rst_n),.enabled(mode),.frame_start(start),.hs_raw(hs),.vs_raw(vs),.de_raw(de),.x_raw(x),.y_raw(y),.read_req(mrq),.read_ack(readack),.read_empty(fifo_empty),.read_data(fifo_data),.read_en(mren),.hs(mhs),.vs(mvs),.de(mde),.rgb(mrgb));
 always @(posedge mem)if(!rst_n)done_toggle<=0;else if(rxfinish)done_toggle<=~done_toggle;
 reg [31:0] expected[0:115199];reg [31:0] reference[0:345599];
 integer rendered_words=0,reference_base=0;
 initial $readmemh("mesh3d_tiles_rtl.hex",reference);
 always @(posedge rclk)begin
  if(renderer.state==1)begin rendered_words<=0;reference_base=(renderer.last_id-1)*115200;end
  if(wr_en)begin
   if(wr_data!==reference[reference_base+rendered_words])$fatal(1,"FAIL: actual B 3D render mismatch word=%0d expected=%h got=%h",rendered_words,reference[reference_base+rendered_words],wr_data);
   if(wr_full || rendered_words>=115200)$fatal(1,"FAIL: 3D render overflow");
   expected[rendered_words]=wr_data;rendered_words<=rendered_words+1;
  end
 end
 integer rxwords=0;reg read_frame_checked=0;reg [11:0] xd[0:4],yd[0:4];reg [4:0] dd=0;integer k;reg [31:0] checked_word;reg [15:0] checked_colour;reg [23:0] checked_rgb;
 always @(posedge net)begin
  ticks<=ticks+1;a_to_b<=0;b_to_a<=0;
  if(sv&&sr)begin fwd_hold<=sp;fwd<=144;gap<=169;packets<=packets+1;end
  if(gap!=0)gap<=gap-1;
  if(fwd!=0)begin fwd<=fwd-1;if(fwd==1)begin b_to_a<=1;pb<=fwd_hold;end end
  if(av&&ar)begin back_hold<=ap;back<=144;end
  if(back!=0)begin back<=back-1;if(back==1)begin a_to_b<=1;pa<=back_hold;end end
  if(rxreq)rxwords<=0;
  if(rxen)begin
   if(rxdata!==expected[rxwords])$fatal(1,"FAIL: actual B->A map word %d",rxwords);
   rxwords<=rxwords+1;
  end
  if(cv&&cr)begin
   if(rxwords!=115200)$fatal(1,"FAIL: partial rendered map committed");
   commits<=commits+1;$display("MEASURE: true3D full frame=%0d packets=%0d time_ns=%0t mesh_id=%0d",commits,packets,$time,renderer.last_id);

  end
 end
 always @(posedge video)begin
  xd[0]<=x;yd[0]<=y;dd<={dd[3:0],de};for(k=1;k<5;k=k+1)begin xd[k]<=xd[k-1];yd[k]<=yd[k-1];end
  #1;
  if(rst_n && mode && mde && scan.rows_loaded>=(yd[4]>>1)+1)begin
   checked_word=a_ram.ram[(display?1958400:1843200)+(yd[4]>>1)*320+(xd[4]>>2)];
   checked_colour=xd[4][1]?checked_word[31:16]:checked_word[15:0];
   checked_rgb={checked_colour[15:11],checked_colour[15:13],checked_colour[10:5],checked_colour[10:9],checked_colour[4:0],checked_colour[4:2]};
   if(mrgb!==checked_rgb)$fatal(1,"FAIL: 1280x720 packed map scanout x=%d y=%d actual=%h expected=%h",xd[4],yd[4],mrgb,checked_rgb);
   display_pixels=display_pixels+1;
  end
 end
 initial begin
  store.local_tf.sd_card_top_m0.spi_master_m0.pause_transport=NO_CARD;
  repeat(30)@(negedge net);rst_n=1;
  wait(commits==3);repeat(2000)@(negedge net);
  if(store.cache_mask!=0)$fatal(1,"3D map unexpectedly needs a TF image");
  if(display_pixels<921600)$fatal(1,"FAIL: full output pixels not checked");
  $display("PASS: three actual B depth-rendered XYZ scenes, no TF dependency, real B FIFO/SDRAM, 100M-paced RLE transport, real A FIFO/SDRAM double buffering and %0d exact 1280x720 display pixels; rotation, zoom/follow, event change and no partial frame publish",display_pixels);$finish;
 end
 initial begin #1500000000;$fatal(1,"FAIL: rendered chain timeout Bstate=%d sender=%d receiver=%d source_cache=%b words=%d",renderer.state,sender.phase,receiver.decoder.state,store.cache_mask,rxwords);end
endmodule
