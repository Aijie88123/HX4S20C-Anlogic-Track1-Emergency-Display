`timescale 1ns/1ps
module tb_tf_on_a_image_chain;
 reg clk=0,aclk=0,net=0,video=0,mem=0,rst_n=0;
 always #10 clk=~clk;always #5 aclk=~aclk;always #20 net=~net;always #6.666666 video=~video;always #4 mem=~mem;
 wire tfav,tfbv,iv,iav;wire [223:0] tfap,tfbp,ip,ackp;reg pav=0,pbv=0;reg [223:0] pa=0,pb=0,ahold,bhold;
 integer aflight=0,bflight=0,agap=0,bgap=0;wire ar=aflight==0&&agap==0,br=bflight==0&&bgap==0;
 always @(posedge net)begin
  pav<=0;pbv<=0;if(agap!=0)agap<=agap-1;if(bgap!=0)bgap<=bgap-1;
  if((tfav||iav)&&ar)begin ahold<=iav?ackp:tfap;aflight<=144;agap<=169;end
  if((tfbv||iv)&&br)begin bhold<=tfbv?tfbp:ip;bflight<=144;bgap<=169;end
  if(aflight!=0)begin aflight<=aflight-1;if(aflight==1)begin pbv<=1;pb<=ahold;end end
  if(bflight!=0)begin bflight<=bflight-1;if(bflight==1)begin pav<=1;pa<=bhold;end end
 end
 a_tf_sector_service #(.SD_CLK_HZ(1000000)) a_reader(.sd_clk(aclk),.net_clk(net),.rst(!rst_n),.online(1'b1),
  .packet_valid(pav),.packet(pa),.stream_valid(tfav),.stream_data(tfap),.stream_ready(ar&&!iav),.sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi());
 wire readreq,readen,readack,readempty,readbusy;wire [31:0] readword;wire [2:0] readrole;wire [4:0] available;wire [159:0] sizes;
 b_media_storage #(.CLK_FREQ_HZ(1000000),.REMOTE_TF(1)) b_storage(.clk(clk),.rst_n(rst_n),.net_clk(net),.net_rst(!rst_n),
  .sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi(),.online(1'b1),.packet_valid(pbv),.packet(pb),
  .tf_stream_valid(tfbv),.tf_stream_data(tfbp),.tf_stream_ready(br),
  .read_req(readreq),.read_en(readen),.read_role(readrole),.read_ack(readack),.read_empty(readempty),.read_data(readword),
  .available(available),.source_sizes(sizes),.source_fault(),.source_fault_recurring(),
  .map_write_req(1'b0),.map_write_en(1'b0),.map_write_cancel(1'b0),.map_write_data(32'd0),
  .map_write_ack(),.map_write_full(),.map_write_done_toggle(),.render_clk(),.render_rst());
 media_image_sender b_sender(.clk(net),.rst(!rst_n),.online(1'b1),.available(available),.source_sizes(sizes),.source_fault(4'd0),.source_fault_recurring(1'b0),
  .packet_valid(pbv),.packet(pb),.stream_valid(iv),.stream_data(ip),.stream_ready(br&&!tfbv),
  .read_req(readreq),.read_ack(readack),.read_empty(readempty),.read_data(readword),.read_en(readen),.read_role(readrole),.read_busy(readbusy));
 wire wrreq,wrack,wrfull,wren,wrfinish,wrcancel,commit,commitready,commitsd,commitreadysd;wire [31:0] wrword;
 wire [2:0] role,staging,display,page;wire [15:0] iw,ih;wire shown;reg done_toggle=0;
 media_image_receiver a_receiver(.clk(net),.rst(!rst_n),.online(1'b1),.packet_valid(pav),.packet(pa),
  .ack_valid(iav),.ack_packet(ackp),.ack_ready(ar),.write_cancel(wrcancel),.write_req(wrreq),.write_ack(wrack),.write_full(wrfull),
  .write_done_toggle(done_toggle),.write_en(wren),.write_data(wrword),.frame_commit_valid(commit),.frame_commit_ready(commitready),
  .commit_role(role),.commit_width(iw),.commit_height(ih),.transfer_active(),.remote_fault(),.remote_fault_recurring());
 media_commit_cdc cdc(.src_clk(net),.dst_clk(aclk),.rst(!rst_n),.src_valid(commit),.src_ready(commitready),.dst_valid(commitsd),.dst_ready(commitreadysd));
 wire rawvs,rawde,rawhs,framestart,hs,vs,de;wire [11:0] rawx,rawy;wire [23:0] rgb;
 a_media_cached_control #(.CLK_FREQ_HZ(1000000)) control(.clk(aclk),.rst(!rst_n),.key_next(1'b1),.key_auto(1'b1),.emergency(1'b0),.vsync(rawvs),.remote_phase(9'd0),
  .incoming_complete(commitsd),.incoming_role(role),.incoming_w(iw),.incoming_h(ih),.incoming_commit_ready(commitreadysd),
  .staging_slot(staging),.display_slot(display),.display_valid(shown),.page_index(page),.disp_src_w(),.disp_src_h(),.disp_src_toggle(),.disp_audio_emergency(),
  .load_nearly_done(),.load_visual_active(),.auto_play_en_out(),.carousel_feedback(),.interval_selection(),.brightness_step_toggle(),.contrast_step_toggle(),.cached_roles(),.state_code());
 wire vrq,vack,ven,vempty;wire [31:0] vword;
 wire initialized,refresh,busy,app_rd,app_wr,rdvalid;wire [20:0] raddr,waddr;wire [31:0] rddata,wdata;wire [3:0] dm;
 frame_read_write #(.ENABLE_WRITE_CANCEL(1),.WRITE_V_FLIP(0)) a_frames(.rst(!rst_n),.mem_clk(mem),.Sdr_init_done(initialized),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_rd_en(app_rd),.App_rd_addr(raddr),.Sdr_rd_en(rdvalid),.Sdr_rd_dout(rddata),
  .App_wr_en(app_wr),.App_wr_addr(waddr),.App_wr_dm(dm),.App_wr_din(wdata),
  .read_clk(video),.read_req(vrq&&shown&&!rawvs),.read_req_ack(vack),.read_finish(),.read_addr_0(21'(display*307200)),.read_addr_1(21'd0),.read_addr_2(21'd0),.read_addr_3(21'd0),
  .read_addr_index(2'd0),.read_len(21'd307200),.read_en(ven),.read_data(vword),.read_empty(vempty),
  .write_clk(net),.write_req(wrreq),.write_req_ack(wrack),.write_finish(wrfinish),.write_addr_0(21'(staging*307200)),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),
  .write_addr_index(2'd0),.write_len(21'd307200),.write_en(wren),.write_data(wrword),.write_full(wrfull),.write_cancel(wrcancel));
 sdram a_ram(.Clk(mem),.Clk_sft(mem),.Rst(!rst_n),.Sdr_init_done(initialized),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_wr_en(app_wr),.App_wr_addr(waddr),.App_wr_dm(dm),.App_wr_din(wdata),.App_rd_en(app_rd),.App_rd_addr(raddr),.Sdr_rd_en(rdvalid),.Sdr_rd_dout(rddata));
 always @(posedge mem)if(!rst_n)done_toggle<=0;else if(wrfinish)done_toggle<=~done_toggle;
 video_scanout_720p scanout(.clk(video),.rst(!rst_n),.read_req(vrq),.read_req_ack(vack),.read_en(ven),.read_data(vword),.read_empty(vempty),
  .hs(hs),.vs(vs),.de(de),.rgb(rgb),.raw_hs(rawhs),.raw_vs(rawvs),.raw_de(rawde),.raw_frame_start(framestart),.raw_x(rawx),.raw_y(rawy));
 integer words=0,pixels=0,shown_frames=0;reg prior_vs=0;reg [11:0] xd[0:4],yd[0:4];integer d,px,r0,r1,b0,b1,sy;reg [23:0] expected;
 always @(posedge net)begin
  if(wrreq)words<=0;
  if(wren)begin px=words%640;if(wrword!=={8'(px^role),8'd0,8'(px+role),8'd0})$fatal(1,"FAIL: A received BMP word %d actual=%h",words,wrword);words<=words+1;end
  if(commit&&words!=307200)$fatal(1,"FAIL: incomplete A image commit");
 end
 always @(posedge video)begin
  prior_vs<=rawvs;if(rawvs&&!prior_vs&&shown)shown_frames<=shown_frames+1;
  xd[0]<=rawx;yd[0]<=rawy;for(d=1;d<5;d=d+1)begin xd[d]<=xd[d-1];yd[d]<=yd[d-1];end
  #1;sy=(yd[4]*2)/3;
  if(shown&&shown_frames>=1&&page==2&&de&&scanout.rows_loaded>=(sy==479?480:sy+2))begin
   px=xd[4]>>1;r0=(px^2)&255;b0=(px+2)&255;r1=(((px==639?px:px+1)^2)&255);b1=((px==639?px:px+1)+2)&255;
   expected={8'(xd[4][0]?(r0+r1)/2:r0),8'd0,8'(xd[4][0]?(b0+b1)/2:b0)};
   if(rgb!==expected)$fatal(1,"FAIL: actual A display x=%d y=%d rgb=%h expected=%h",xd[4],yd[4],rgb,expected);pixels=pixels+1;
  end
 end
 initial begin
  repeat(20)@(negedge net);rst_n=1;wait(pixels>=921600);@(negedge net);
  if(!shown||page!=2||available!=31)$fatal(1,"FAIL: complete image cache/display");
  $display("PASS: TF on A -> real SPI/FAT sector transport -> B BMP/scaling/cache -> RGB888 frame transfer -> A real FIFO/SDRAM/VS commit -> 1280x720 bilinear display: %0d independently checked output pixels",pixels);$finish;
 end
 initial begin #2000000000;$fatal(1,"FAIL: image chain timeout Bcache=%b sender=%d receiver=%d shown=%b pixels=%d",available,b_sender.state,a_receiver.state,shown,pixels);end
endmodule
