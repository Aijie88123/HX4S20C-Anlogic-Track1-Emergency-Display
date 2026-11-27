// Full-display component regression: byte-level physical-SPI surrogate and
// accelerated packet-boundary transport; wire timing/FCS independently tested.
`timescale 1ns/1ps
module tb_full_display;
 reg clk=0,aclk=0,net=0,video=0,mem=0,rst_n=0,emergency=0;
 always #10 clk=~clk;always #5 aclk=~aclk;always #20 net=~net;always #6.666666 video=~video;always #4 mem=~mem;
 wire tfav,tfbv,iv,iav;wire [223:0] tfap,tfbp,ip,ackp;reg pav=0,pbv=0;reg [223:0] pa=0,pb=0,ahold,bhold;
 integer aflight=0,bflight=0,agap=0,bgap=0;wire ar=aflight==0&&agap==0,br=bflight==0&&bgap==0;
 always @(posedge net)begin
  pav<=0;pbv<=0;if(agap!=0)agap<=agap-1;if(bgap!=0)bgap<=bgap-1;
  if((tfav||iav)&&ar)begin ahold<=iav?ackp:tfap;aflight<=8;agap<=12;end
  if((tfbv||iv)&&br)begin bhold<=tfbv?tfbp:ip;bflight<=8;bgap<=12;end
  if(aflight!=0)begin aflight<=aflight-1;if(aflight==1)begin pbv<=1;pb<=ahold;end end
  if(bflight!=0)begin bflight<=bflight-1;if(bflight==1)begin pav<=1;pa<=bhold;end end
 end
 a_tf_sector_service #(.SD_CLK_HZ(1000000)) a_reader(.sd_clk(aclk),.net_clk(net),.rst(!rst_n),.online(1'b1),
  .packet_valid(pav),.packet(pa),.stream_valid(tfav),.stream_data(tfap),.stream_ready(ar&&!iav),.sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi());
 wire readreq,readen,readack,readempty,readbusy;wire [31:0] readword;wire [2:0] readrole;wire [5:0] available;wire [191:0] sizes;
 wire [3:0] source_fault;wire recurring;
 b_media_storage #(.CLK_FREQ_HZ(50000000),.REMOTE_TF(1),.IMAGE_ROLES(6),.NUMBERED_SIX(1),.EMERGENCY_PRIORITY(1)) b_storage(.clk(clk),.rst_n(rst_n),.net_clk(net),.net_rst(!rst_n),
  .sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi(),.online(1'b1),.packet_valid(pbv),.packet(pb),
  .tf_stream_valid(tfbv),.tf_stream_data(tfbp),.tf_stream_ready(br),
  .read_req(readreq),.read_en(readen),.read_role(readrole),.read_ack(readack),.read_empty(readempty),.read_data(readword),
  .available(available),.source_sizes(sizes),.source_fault(source_fault),.source_fault_recurring(recurring),.priority_emergency(emergency),
  .map_write_req(1'b0),.map_write_en(1'b0),.map_write_cancel(1'b0),.map_write_data(32'd0),
  .map_write_ack(),.map_write_full(),.map_write_done_toggle(),.render_clk(),.render_rst());
 media_image_sender #(.IMAGE_ROLES(6),.EMERGENCY_PRIORITY(1)) b_sender(.clk(net),.rst(!rst_n),.online(1'b1),.available(available),.source_sizes(sizes),.source_fault(source_fault),.source_fault_recurring(recurring),.priority_emergency(emergency),
  .packet_valid(pbv),.packet(pb),.stream_valid(iv),.stream_data(ip),.stream_ready(br&&!tfbv),
  .read_req(readreq),.read_ack(readack),.read_empty(readempty),.read_data(readword),.read_en(readen),.read_role(readrole),.read_busy(readbusy));
 wire wrreq,wrack,wrfull,wren,wrfinish,wrcancel,commit,commitready,commitsd,commitreadysd;wire [31:0] wrword;
 wire [2:0] role,staging,display,page;wire [15:0] iw,ih;wire shown;reg done_toggle=0;
 media_image_receiver #(.IMAGE_ROLES(6),.PACK_RGB888(1)) a_receiver(.clk(net),.rst(!rst_n),.online(1'b1),.packet_valid(pav),.packet(pa),
  .ack_valid(iav),.ack_packet(ackp),.ack_ready(ar),.write_cancel(wrcancel),.write_req(wrreq),.write_ack(wrack),.write_full(wrfull),
  .write_done_toggle(done_toggle),.write_en(wren),.write_data(wrword),.frame_commit_valid(commit),.frame_commit_ready(commitready),
  .commit_role(role),.commit_width(iw),.commit_height(ih),.transfer_active(),.remote_fault(),.remote_fault_recurring());
 media_commit_cdc cdc(.src_clk(net),.dst_clk(aclk),.rst(!rst_n),.src_valid(commit),.src_ready(commitready),.dst_valid(commitsd),.dst_ready(commitreadysd));
 wire rawvs,rawde,rawhs,framestart,hs,vs,de,mapready;wire [5:0] cached;wire [11:0] rawx,rawy;wire [23:0] rgb;
 a_media_cached_control #(.CLK_FREQ_HZ(1000000),.IMAGE_ROLES(6),.EMER_SEQUENCE(1),.STRICT_PRELUDE(1),.STRICT_ORDER(1)) control(.clk(aclk),.rst(!rst_n),.key_next(1'b1),.key_auto(1'b1),.emergency(emergency),.vsync(rawvs),.remote_phase(9'd0),
  .incoming_complete(commitsd),.incoming_role(role),.incoming_w(iw),.incoming_h(ih),.incoming_commit_ready(commitreadysd),
  .staging_slot(staging),.display_slot(display),.display_valid(shown),.page_index(page),.disp_src_w(),.disp_src_h(),.disp_src_toggle(),.disp_audio_emergency(),
  .load_nearly_done(),.load_visual_active(),.auto_play_en_out(),.carousel_feedback(),.interval_selection(),.brightness_step_toggle(),.contrast_step_toggle(),.cached_roles(cached),.state_code(),.emergency_map_ready(mapready));
 wire vrq,vack,ven,vempty;wire [31:0] vword;
 wire initialized,refresh,busy,app_rd,app_wr,rdvalid;wire [20:0] raddr,waddr;wire [31:0] rddata,wdata;wire [3:0] dm;
 frame_read_write #(.ENABLE_WRITE_CANCEL(1),.WRITE_V_FLIP(0)) a_frames(.rst(!rst_n),.mem_clk(mem),.Sdr_init_done(initialized),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_rd_en(app_rd),.App_rd_addr(raddr),.Sdr_rd_en(rdvalid),.Sdr_rd_dout(rddata),
  .App_wr_en(app_wr),.App_wr_addr(waddr),.App_wr_dm(dm),.App_wr_din(wdata),
  .read_clk(video),.read_req(vrq&&shown&&!rawvs),.read_req_ack(vack),.read_finish(),.read_addr_0(21'(display*230400)),.read_addr_1(21'd0),.read_addr_2(21'd0),.read_addr_3(21'd0),
  .read_addr_index(2'd0),.read_len(21'd230400),.read_en(ven),.read_data(vword),.read_empty(vempty),
  .write_clk(net),.write_req(wrreq),.write_req_ack(wrack),.write_finish(wrfinish),.write_addr_0(21'(staging*230400)),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),
  .write_addr_index(2'd0),.write_len(21'd230400),.write_en(wren),.write_data(wrword),.write_full(wrfull),.write_cancel(wrcancel));
 sdram a_ram(.Clk(mem),.Clk_sft(mem),.Rst(!rst_n),.Sdr_init_done(initialized),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_wr_en(app_wr),.App_wr_addr(waddr),.App_wr_dm(dm),.App_wr_din(wdata),.App_rd_en(app_rd),.App_rd_addr(raddr),.Sdr_rd_en(rdvalid),.Sdr_rd_dout(rddata));
 always @(posedge mem)if(!rst_n)done_toggle<=0;else if(wrfinish)done_toggle<=~done_toggle;
 wire unpack_en,unpack_empty;wire [31:0] unpack_data;
 rgb888_frame_unpack unpack(.clk(video),.rst(!rst_n),.restart(vrq),.word_empty(vempty),.word_data(vword),.word_read(ven),
  .pixel_read(unpack_en),.pixel_empty(unpack_empty),.pixel_data(unpack_data));
 video_scanout_720p scanout(.clk(video),.rst(!rst_n),.read_req(vrq),.read_req_ack(vack),.read_en(unpack_en),.read_data(unpack_data),.read_empty(unpack_empty),
  .hs(hs),.vs(vs),.de(de),.rgb(rgb),.raw_hs(rawhs),.raw_vs(rawvs),.raw_de(rawde),.raw_frame_start(framestart),.raw_x(rawx),.raw_y(rawy));
 // Independent reference is derived directly from the saved BMP bytes,
 // without importing the RTL parser, scaler or video interpolation code.
 reg [31:0] golden[0:1843199];
 initial $readmemh("storage_recovery_vectors/full_expected.hex",golden);
 reg previous_commit=0;integer words=0;reg [31:0] expected_word;integer lane,byte_index,gpixel,channel;
 reg [23:0] gp;
 always @(posedge net)begin
  previous_commit<=commit;
  if(wrreq)words<=0;
  if(wren)begin
   for(lane=0;lane<4;lane=lane+1)begin
    byte_index=words*4+lane;gpixel=byte_index/3;channel=byte_index%3;
    gp=golden[role*307200+gpixel][31:8];
    expected_word[lane*8 +:8]=gp>>(channel*8);
   end
   if(wrword!==expected_word)$fatal(1,"FAIL: full real-BMP packed word role=%d word=%d got=%h expected=%h",role,words,wrword,expected_word);
   words<=words+1;
  end
  if(commit && !previous_commit)begin
   if(words!=230400)$fatal(1,"FAIL: incomplete packed frame commit role=%d words=%d",role,words);
   $display("TRACE: full real BMP packed A frame complete role=%0d original=%0dx%0d at=%0t",role,iw,ih,$time);
  end
 end
 function [23:0] expected_pixel;
  input integer which,ox,oy;
  integer sx,sx1,sy,sy1,weight,c,t,b,value;
  reg [23:0] p00,p01,p10,p11,result;
  begin
   sx=ox/2;sx1=sx==639?639:sx+1;sy=(oy*2)/3;sy1=sy==479?479:sy+1;
   p00=golden[which*307200+sy*640+sx][31:8];p01=golden[which*307200+sy*640+sx1][31:8];
   p10=golden[which*307200+sy1*640+sx][31:8];p11=golden[which*307200+sy1*640+sx1][31:8];
   weight=sy==479?0:oy%3==1?171:oy%3==2?85:0;
   for(c=0;c<3;c=c+1)begin
    t=(p00>>(8*c))&255;b=(p10>>(8*c))&255;
    if(ox%2)begin t=(t+((p01>>(8*c))&255))/2;b=(b+((p11>>(8*c))&255))/2;end
    // Integer weighted mean with nearest rounding, including negative delta.
    value=((256-weight)*t+weight*b+128)/256;result[c*8+:8]=value;
   end
   expected_pixel=result;
  end
 endfunction
 reg [11:0] xd[0:4],yd[0:4];integer d;
 reg [5:0] checked=0;integer frames=0,pixels=0,count=0,capture_role=7,stable_frames=0;
 reg capturing=0,prior_vs=0;reg [2:0] last_page=7;
 reg [23:0] expected;
 always @(posedge video)begin
  if(!rst_n)begin capturing=0;prior_vs=0;stable_frames=0;last_page=7;end
  else begin
   if(shown && page!=last_page)begin
    $display("TRACE: full display page changed to role=%0d at=%0t",page,$time);
    last_page=page;stable_frames=0;
   end else if(rawvs&&!prior_vs&&shown)stable_frames=stable_frames+1;
   prior_vs=rawvs;
   xd[0]<=rawx;yd[0]<=rawy;for(d=1;d<5;d=d+1)begin xd[d]<=xd[d-1];yd[d]<=yd[d-1];end
   #1;
   if(de && shown)begin
    if(!capturing && xd[4]==0 && yd[4]==0 && stable_frames>=1 && !checked[page] && (page==2||page==0||page==1))begin
     capture_role=page;count=0;capturing=1;
     if(page==0&&!checked[2])$fatal(1,"FAIL: emergency 05 preceded complete ordinary 01");
     if(page==1&&!checked[0])$fatal(1,"FAIL: emergency 06 preceded complete emergency 05");
     $display("TRACE: verifying full 1280x720 real-BMP frame role=%0d at=%0t",capture_role,$time);
    end
    if(capturing)begin
     if(page!=capture_role||xd[4]!=count%1280||yd[4]!=count/1280)$fatal(1,"FAIL: partial/torn 720p frame role=%d x=%d y=%d count=%d",capture_role,xd[4],yd[4],count);
     expected=expected_pixel(capture_role,xd[4],yd[4]);
     if(rgb!==expected)$fatal(1,"FAIL: full 720p bilinear role=%d x=%d y=%d got=%h expected=%h loaded=%d",capture_role,xd[4],yd[4],rgb,expected,scanout.rows_loaded);
     count=count+1;pixels=pixels+1;
     if(count==921600)begin checked[capture_role]=1;frames=frames+1;capturing=0;
      $display("TRACE: PASS full 720p real-BMP role=%0d pixels=%0d at=%0t",capture_role,count,$time);
     end
    end
   end
  end
 end
 integer committed05=0,committed06=0,late05_checks=0,late06_checks=0;
 always @(posedge aclk)if(rst_n)begin
  if(source_fault!=0)$fatal(1,"FAIL: real saved BMP source fault=%d",source_fault);
  if(commitsd&&commitreadysd)begin if(role==0)committed05=1;if(role==1)committed06=1;end
  if(emergency && !cached[0])begin
   if(mapready||page==1)$fatal(1,"FAIL: strict prelude skipped late 05");late05_checks=late05_checks+1;
  end
  if(emergency&&cached[0]&&!cached[1])begin
   if(mapready)$fatal(1,"FAIL: strict prelude skipped late 06");late06_checks=late06_checks+1;
  end
  if(mapready && (!checked[0]||!checked[1]))$fatal(1,"FAIL: map became ready before both full emergency frames");
 end
 initial begin
  repeat(20)@(negedge net);rst_n=1;
  wait(checked[2]);@(negedge net);emergency=1;
  $display("TRACE: entering emergency after verified ordinary 01; waiting for real late 05/06 at=%0t",$time);
  wait(checked[0]&&checked[1]&&mapready);@(negedge net);
  if(frames!=3||pixels!=2764800||!committed05||!committed06||late05_checks==0||late06_checks==0)
   $fatal(1,"FAIL: complete full-display coverage frames=%d pixels=%d late05=%d late06=%d",frames,pixels,late05_checks,late06_checks);
  $display("PASS: six saved real multirow BMP fixtures (06=800x600) -> A sector service -> B FAT32/fragmented BMP/scaling/real FIFO/SDRAM -> six-role emergency-priority sender -> packed A receiver/real FIFO/SDRAM/strict VS control -> three complete 1280x720 bilinear frames 01,05,06: all 2764800 pixels independently verified against source-derived golden; strict order/prelude waited for both late complete frames and map-ready followed 06 dwell");
  $finish;
 end
 initial begin #(64'd20000000000);$fatal(1,"FAIL full display timeout Bcache=%b sender=%d receiver=%d page=%d checked=%b pixels=%d",available,b_sender.state,a_receiver.state,page,checked,pixels);end
endmodule
