`timescale 1ns/1ps
module tb_control25_chain;
 reg clk=0,aclk=0,net=0,video=0,mem=0,rst_n=0;
 reg priority_emergency=1;always #10 clk=~clk;always #5 aclk=~aclk;always #20 net=~net;always #6.666666 video=~video;always #4 mem=~mem;
 wire tfav,tfbv,iv,iav;wire [223:0] tfap,tfbp,ip,ackp;reg pav=0,pbv=0;reg [223:0] pa=0,pb=0,ahold,bhold;
 integer aflight=0,bflight=0,agap=0,bgap=0;wire ar=aflight==0&&agap==0,br=bflight==0&&bgap==0;
 always @(posedge net)begin
  pav<=0;pbv<=0;if(agap!=0)agap<=agap-1;if(bgap!=0)bgap<=bgap-1;
  if((tfav||iav)&&ar)begin ahold<=iav?ackp:tfap;aflight<=144;agap<=169;end
  if((tfbv||iv)&&br)begin bhold<=tfbv?tfbp:ip;bflight<=144;bgap<=169;end
  if(aflight!=0)begin aflight<=aflight-1;if(aflight==1)begin pbv<=1;pb<=ahold;end end
  if(bflight!=0)begin bflight<=bflight-1;if(bflight==1)begin pav<=1;pa<=bhold;end end
 end
 a_tf_sector_service_timed #(.SD_CLK_HZ(1000000)) a_reader(.sd_clk(aclk),.net_clk(net),.rst(!rst_n),.online(1'b1),
  .packet_valid(pav),.packet(pa),.stream_valid(tfav),.stream_data(tfap),.stream_ready(ar&&!iav),.sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi());
 wire readreq,readen,readack,readempty,readbusy;wire [31:0] readword;wire [2:0] readrole;wire [7:0] available;wire [255:0] sizes;
 b_media_storage #(.CLK_FREQ_HZ(1000000),.REMOTE_TF(1),.IMAGE_ROLES(8),.PREV_PLAYLIST(1),.PACK_SOURCE(1),.FAST_NORMALIZE(0),.EMERGENCY_PRIORITY(1)) b_storage(.clk(clk),.rst_n(rst_n),.net_clk(net),.net_rst(!rst_n),
  .sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi(),.online(1'b1),.packet_valid(pbv),.packet(pb),
  .tf_stream_valid(tfbv),.tf_stream_data(tfbp),.tf_stream_ready(br),
  .read_req(readreq),.read_en(readen),.read_role(readrole),.read_map(1'b0),.read_ack(readack),.read_empty(readempty),.read_data(readword),
  .available(available),.source_sizes(sizes),.priority_emergency(priority_emergency),.source_fault(),.source_fault_recurring(),
  .map_write_req(1'b0),.map_write_en(1'b0),.map_write_cancel(1'b0),.map_write_data(32'd0),
  .map_write_ack(),.map_write_full(),.map_write_done_toggle(),.render_clk(),.render_rst());
 media_image_sender #(.IMAGE_ROLES(8)) b_sender(.clk(net),.rst(!rst_n),.online(1'b1),.available(available & 8'b00000100),.source_sizes(sizes),.source_fault(4'd0),.source_fault_recurring(1'b0),
  .packet_valid(pbv),.packet(pb),.stream_valid(iv),.stream_data(ip),.stream_ready(br&&!tfbv),
  .read_req(readreq),.read_ack(readack),.read_empty(readempty),.read_data(readword),.read_en(readen),.read_role(readrole),.read_busy(readbusy));
 wire wrreq,wrack,wrfull,wren,wrfinish,wrcancel,commit,commitready,commitsd,commitreadysd;wire [31:0] wrword;
 wire [2:0] role,staging,display,page;wire [15:0] iw,ih;wire shown;reg done_toggle=0;
 media_image_receiver #(.IMAGE_ROLES(8),.PACK_RGB888(1),.IMMUTABLE_CACHE(1)) a_receiver(.cache_reset(!rst_n),.clk(net),.rst(!rst_n),.online(1'b1),.packet_valid(pav),.packet(pa),
  .ack_valid(iav),.ack_packet(ackp),.ack_ready(ar),.write_cancel(wrcancel),.write_req(wrreq),.write_ack(wrack),.write_full(wrfull),
  .write_done_toggle(done_toggle),.write_en(wren),.write_data(wrword),.frame_commit_valid(commit),.frame_commit_ready(commitready),
  .commit_role(role),.commit_width(iw),.commit_height(ih),.transfer_active(),.remote_fault(),.remote_fault_recurring());
 media_commit_cdc cdc(.src_clk(net),.dst_clk(net),.rst(!rst_n),.src_valid(commit),.src_ready(commitready),.dst_valid(commitsd),.dst_ready(commitreadysd));
 wire rawvs,rawde,rawhs,framestart,hs,vs,de;wire [11:0] rawx,rawy;wire [23:0] rgb;
 a_media_cached_control #(.CLK_FREQ_HZ(25000000),.IMAGE_ROLES(8),.FIXED_SLOTS(1),.STRICT_ORDER(1)) control(.clk(net),.rst(!rst_n),.key_next(1'b1),.key_auto(1'b1),.emergency(1'b0),.vsync(rawvs),.remote_phase(9'd0),
  .incoming_complete(commitsd),.incoming_role(role),.incoming_w(iw),.incoming_h(ih),.incoming_commit_ready(commitreadysd),
  .staging_slot(staging),.display_slot(display),.display_valid(shown),.page_index(page),.disp_src_w(),.disp_src_h(),.disp_src_toggle(),.disp_audio_emergency(),
  .load_nearly_done(),.load_visual_active(),.auto_play_en_out(),.carousel_feedback(),.interval_selection(),.brightness_step_toggle(),.contrast_step_toggle(),.cached_roles(),.state_code());
 wire vrq,vack,ven,vempty;wire [31:0] vword;
 wire uwread,uwempty;wire [31:0] uword;
 rgb888_frame_unpack display_unpack(.clk(video),.rst(!rst_n),.restart(vrq),.word_empty(uwempty),.word_data(uword),.word_read(uwread),
  .pixel_read(ven),.pixel_empty(vempty),.pixel_data(vword));
 wire initialized,refresh,busy,app_rd,app_wr,rdvalid;wire [20:0] raddr,waddr;wire [31:0] rddata,wdata;wire [3:0] dm;
 frame_read_write #(.ENABLE_WRITE_CANCEL(1),.WRITE_V_FLIP(0)) a_frames(.rst(!rst_n),.mem_clk(mem),.Sdr_init_done(initialized),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_rd_en(app_rd),.App_rd_addr(raddr),.Sdr_rd_en(rdvalid),.Sdr_rd_dout(rddata),
  .App_wr_en(app_wr),.App_wr_addr(waddr),.App_wr_dm(dm),.App_wr_din(wdata),
  .read_clk(video),.read_req(vrq&&shown&&!rawvs),.read_req_ack(vack),.read_finish(),.read_addr_0(21'(display*230400)),.read_addr_1(21'd0),.read_addr_2(21'd0),.read_addr_3(21'd0),
  .read_addr_index(2'd0),.read_len(21'd230400),.read_en(uwread),.read_data(uword),.read_empty(uwempty),
  .write_clk(net),.write_req(wrreq),.write_req_ack(wrack),.write_finish(wrfinish),.write_addr_0(21'(role*230400)),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),
  .write_addr_index(2'd0),.write_len(21'd230400),.write_en(wren),.write_data(wrword),.write_full(wrfull),.write_cancel(wrcancel));
 sdram a_ram(.Clk(mem),.Clk_sft(~mem),.Rst(!rst_n),.Sdr_init_done(initialized),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_wr_en(app_wr),.App_wr_addr(waddr),.App_wr_dm(dm),.App_wr_din(wdata),.App_rd_en(app_rd),.App_rd_addr(raddr),.Sdr_rd_en(rdvalid),.Sdr_rd_dout(rddata));
 always @(posedge mem)if(!rst_n)done_toggle<=0;else if(wrfinish)done_toggle<=~done_toggle;
 video_scanout_720p scanout(.clk(video),.rst(!rst_n),.read_req(vrq),.read_req_ack(vack),.read_en(ven),.read_data(vword),.read_empty(vempty),
  .hs(hs),.vs(vs),.de(de),.rgb(rgb),.raw_hs(rawhs),.raw_vs(rawvs),.raw_de(rawde),.raw_frame_start(framestart),.raw_x(rawx),.raw_y(rawy));

 sdram_pin_model a_memory(.clk(a_ram.SDRAM_CLK),.ras(a_ram.SDR_RAS),.cas(a_ram.SDR_CAS),.we(a_ram.SDR_WE),.address(a_ram.SDR_ADDR),.bank(a_ram.SDR_BA),.dm(a_ram.SDR_DM),.dq(a_ram.SDR_DQ));
 sdram_pin_model b_memory(.clk(b_storage.U3.SDRAM_CLK),.ras(b_storage.U3.SDR_RAS),.cas(b_storage.U3.SDR_CAS),.we(b_storage.U3.SDR_WE),.address(b_storage.U3.SDR_ADDR),.bank(b_storage.U3.SDR_BA),.dm(b_storage.U3.SDR_DM),.dq(b_storage.U3.SDR_DQ));
 initial begin repeat(40)begin #5000000;$display("NATIVE_STATE: Bstate=%0d found=%h cached=%h busy=%b ref=%b wrstate=%0d wrwords=%0d init=%b Astate=%0d Abusy=%b Aref=%b Awstate=%0d", b_storage.state,b_storage.found_mask,available,b_storage.busy,b_storage.refresh,b_storage.u_frames.frame_fifo_write_m0.state,b_storage.u_frames.frame_fifo_write_m0.write_cnt,b_storage.initialized,a_receiver.state,busy,refresh,a_frames.frame_fifo_write_m0.state);end end
 integer words=0,pixels=0,shown_frames=0;reg prior_vs=0;reg [7:0] committed=0;integer bi,bytepos;
 reg [23:0] expected;reg [31:0] expected_word;
 always @(posedge net)begin
  if(wrreq)words<=0;
  if(wren)begin
   expected={8'(role+16),8'(role+67),8'(role+123)};
   for(bi=0;bi<4;bi=bi+1)expected_word[bi*8+:8]=expected>>(8*((words*4+bi)%3));
   if(wrword!==expected_word)$fatal(1,"FAIL: received packed RGB888 role=%0d word=%0d got=%h expected=%h",role,words,wrword,expected_word);
   words<=words+1;
  end
  if(commit && commitready)begin
   if(words!=230400)$fatal(1,"FAIL: incomplete compact frame");
   committed[role]<=1;$display("TRACE: A complete role=%0d %0dx%0d",role,iw,ih);
  end
 end
 always @(posedge video)begin
  prior_vs<=rawvs;if(rawvs&&!prior_vs&&shown)shown_frames<=shown_frames+1;
  #1;
  if(shown && shown_frames>=1 && de && scanout.rows_loaded>=480)begin
   expected={8'(page+16),8'(page+67),8'(page+123)};
   if(rgb!==expected)$fatal(1,"FAIL: actual HDMI RGB got=%h expected=%h page=%0d",rgb,expected,page);
   pixels=pixels+1;
  end
 end
 initial begin
  if(control.DIV!=25000)$fatal(1,"incorrect 25MHz millisecond timebase");
  repeat(20)@(negedge net);rst_n=1;
  wait(available==3);repeat(1000)@(negedge net);
  if(available!=3 || b_storage.state!=2)$fatal(1,"FAIL: ordinary normalization did not yield to B map priority");
  priority_emergency=0;
  wait(committed[2] && pixels>100000 && available==255);@(negedge net);
  if(available!=255)$fatal(1,"FAIL: B cache incomplete");
  for(bi=0;bi<8;bi=bi+1)begin
   expected={8'(bi+16),8'(bi+67),8'(bi+123)};
   for(bytepos=0;bytepos<230400;bytepos=bytepos+1)begin
    case(bytepos%3)
     0:expected_word={expected[7:0],expected};
     1:expected_word={expected[15:0],expected[23:8]};
     2:expected_word={expected,expected[23:16]};
    endcase
    if(b_memory.memory[bi*230400+bytepos]!==expected_word)$fatal(1,"FAIL: B full packed source cache role=%0d word=%0d",bi,bytepos);
   end
  end
  $display("PASS: A physical sector requests -> v9 Ethernet TF RPC -> B PREV_BMP/FAT/BMP/normalize/packed SDRAM -> eight normalized lossless RGB888 source frames; first full image transfer -> A fixed full-frame caches and bilinear HDMI pixels=%0d",pixels);
  $finish;
 end
 initial begin #2000000000;$fatal(1,"FAIL: full eight-image chain timeout B=%b parser=%0d fault=%0d sender=%0d receiver=%0d commits=%b pixels=%0d",available,b_storage.bmp_read_m0.state,b_storage.fault,b_sender.state,a_receiver.state,committed,pixels);end
initial begin
 repeat(10)begin #10000000;$display("TRACE: t=%0t Bcache=%b parser=%0d source=%0d fault=%0d err=%0d sender=%0d rx=%0d Awords=%0d",$time,available,b_storage.bmp_read_m0.state,b_storage.state,b_storage.fault,b_storage.bmp_read_m0.scan_error_code,b_sender.state,a_receiver.state,words);end
end
endmodule
