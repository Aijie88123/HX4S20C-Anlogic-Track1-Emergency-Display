`timescale 1ns/1ps
module tb_scan_qualified_starve;
 reg mem=0,phase=1,net=0,video=0,rst=1,scan_rst=1;
 always #4 begin mem=~mem;phase=~phase;end
 always #20 net=~net;always #6.666666 video=~video;
 wire ready,refresh,busy,rv,wr,rr;wire [31:0] rd,wd;wire [20:0] wa,ra;wire [3:0] dm;
 wire sclk,ras,cas,we;wire [10:0] adr;wire [1:0] bank;wire [3:0] pins_dm;wire [31:0] dq;
 sdram_pin_model memory(.clk(sclk),.ras(ras),.cas(cas),.we(we),.address(adr),.bank(bank),.dm(pins_dm),.dq(dq));
 sdram ram(.SDRAM_CLK(sclk),.SDR_CKE(),.SDR_RAS(ras),.SDR_CAS(cas),.SDR_WE(we),.SDR_BA(bank),.SDR_ADDR(adr),.SDR_DM(pins_dm),.SDR_DQ(dq),
  .Clk(mem),.Clk_sft(phase),.Rst(rst),.Sdr_init_done(ready),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_wr_en(wr),.App_wr_addr(wa),.App_wr_dm(dm),.App_wr_din(wd),.App_rd_en(rr),.App_rd_addr(ra),.Sdr_rd_en(rv),.Sdr_rd_dout(rd));
 wire display_ready;reg qualified_guard=0;
 reg wreq=0,wen=0;reg [31:0] data=0;reg [20:0] wbase=460800,wlen=230400;
 wire wack,wfull,finish,rack,empty;wire [31:0] pixels;wire rreq,ren,rawvs;
 frame_read_write #(.ENABLE_WRITE_CANCEL(1),.WRITE_V_FLIP(0),.ENABLE_GEOMETRY_GUARD(1)) frames(
  .geometry_mode(qualified_guard),.rst(rst),.mem_clk(mem),.Sdr_init_done(ready),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_rd_en(rr),.App_rd_addr(ra),.Sdr_rd_en(rv),.Sdr_rd_dout(rd),.read_clk(video),.read_req(rreq&&!rawvs),.read_req_ack(rack),.read_finish(),
  .read_addr_0(21'd460800),.read_addr_1(21'd0),.read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),.read_len(21'd230400),.read_en(ren),.read_data(pixels),.read_empty(empty),
  .App_wr_en(wr),.App_wr_addr(wa),.App_wr_din(wd),.App_wr_dm(dm),.write_clk(net),.write_req(wreq),.write_req_ack(wack),.write_finish(finish),
  .write_addr_0(wbase),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),.write_addr_index(2'd0),.write_len(wlen),.write_en(wen),.write_data(data),.write_full(wfull),.write_cancel(1'b0),.write_flip(1'b0));
 integer frames_checked=0;reg supply_stall=0;reg [31:0] random_word=32'h7125abcd;integer forced_pause=0;reg injected=0;
 always @(negedge video)begin
  random_word={random_word[30:0],random_word[31]^random_word[21]^random_word[1]^random_word[0]};
  if(!scan_rst && frames_checked==1 && scan.v_cnt==100 && scan.h_cnt==0 && !injected)begin forced_pause=22500;injected=1;end
  if(forced_pause>0)begin supply_stall=1;forced_pause=forced_pause-1;end
  else supply_stall=random_word[5:0]==0;
 end
 wire pen,pempty;wire [31:0] pdata;wire hs,vs,de,rawde,rawhs,start,pready;wire [23:0] rgb;wire [11:0] rawx,rawy;
 rgb888_frame_unpack unpack(.clk(video),.rst(scan_rst),.restart(rreq),.word_empty(empty||supply_stall),.word_data(pixels),.word_read(ren),.pixel_read(pen),.pixel_empty(pempty),.pixel_data(pdata));
 video_scanout_720p scan(.clk(video),.rst(scan_rst),.read_req(rreq),.read_req_ack(rack),.read_en(pen),.read_data(pdata),.read_empty(pempty),
  .hs(hs),.vs(vs),.de(de),.rgb(rgb),.pixel_ready(pready),.raw_hs(rawhs),.raw_vs(rawvs),.raw_de(rawde),.raw_frame_start(start),.raw_x(rawx),.raw_y(rawy));
 always @(posedge video or posedge rst)if(rst)qualified_guard<=0;else if(display_ready)qualified_guard<=1;
 startup_display_qualifier qualification(.clk(video),.rst(scan_rst),.image_complete(!scan_rst),.normal_active(1'b1),.frame_sync(rawvs),.pixel_de(de),.pixel_ready(pready),.hdmi_ready(1'b1),.display_ready(display_ready));
 integer guarded_cycles=0,unsafe_after=0;reg old_unsafe=0;
 always @(posedge mem)begin
   if(frames.geometry_mode_sync[1])guarded_cycles=guarded_cycles+1;
   old_unsafe=frames.geometry_mode_sync[1] && frames.frame_fifo_read_m0.state==2 && (busy||refresh);
   #1;if(old_unsafe && frames.frame_fifo_read_m0.state==3)unsafe_after=unsafe_after+1;
 end

 function [23:0] source_pixel(input integer x,y);
 reg [31:0] h;begin h=(x+640*y)*32'h174625a9;source_pixel={1'b0,h[22:16],1'b0,h[14:8],1'b0,h[6:0]};end endfunction
 function [31:0] source_word(input integer n);
 integer j,b,pi;reg [23:0] p;begin
  for(j=0;j<4;j=j+1)begin b=n*4+j;pi=b/3;p=source_pixel(pi%640,pi/640);source_word[j*8+:8]=p>>((b%3)*8);end
 end endfunction
 function [23:0] expected_pixel(input integer ox,oy);
 integer sx,sx1,sy,sy1,weight,c,t,b,value;reg [23:0] p00,p01,p10,p11,result;begin
  sx=ox/2;sx1=sx==639?639:sx+1;sy=(oy*2)/3;sy1=sy==479?479:sy+1;
  p00=source_pixel(sx,sy);p01=source_pixel(sx1,sy);p10=source_pixel(sx,sy1);p11=source_pixel(sx1,sy1);
  weight=sy==479?0:oy%3==1?171:oy%3==2?85:0;
  for(c=0;c<3;c=c+1)begin t=(p00>>(8*c))&255;b=(p10>>(8*c))&255;
   if(ox%2)begin t=(t+((p01>>(8*c))&255))/2;b=(b+((p11>>(8*c))&255))/2;end
   value=((256-weight)*t+weight*b+128)/256;result[c*8+:8]=value;
  end expected_pixel=result;
 end endfunction
 integer starved_pixels=0,ready_pixels=0;integer refs=0,checked=0,writes=0,pcnt=0,wcnt=0,collisions=0;reg protect=0;
 always @(posedge sclk)if(ready && {ras,cas,we}==3'b001)refs=refs+1;
 always @(posedge sclk)if(protect && ({ras,cas,we}==3'b100 || memory.write_left!=0))begin
  if(({ras,cas,we}==3'b100 ? memory.index : memory.wp)<1843200)$fatal(1,"map overwrite of immutable cache");
 end
 task write_frame(input integer base,input integer words,input integer seed);integer n;begin
  @(negedge net);wbase=base;wlen=words;wreq=1;wait(wack);@(negedge net);wreq=0;repeat(16)@(negedge net);
  for(n=0;n<words;n=n+1)begin while(wfull)begin wen=0;@(negedge net);end
   wen=1;data=base==460800?source_word(n):seed+n;@(negedge net);
  end wen=0;wait(finish);repeat(32)@(negedge net);writes=writes+1;
 end endtask
 reg pd=0,wdly=0;reg [11:0] xd[0:4],yd[0:4];integer d;reg [23:0] expected;
 always @(posedge video)begin
  if(scan_rst)begin pd<=0;wdly<=0;pcnt=0;wcnt=0;end
  else begin
   if(rreq)begin pcnt=0;wcnt=0;end
   if(ren&&!empty)begin
    if(wcnt>=230400)$fatal(1,"too many words");wcnt=wcnt+1;
   end
   pd<=pen&&!pempty;
   if(pd)begin
    if(pdata!=={source_pixel(pcnt%640,pcnt/640),8'd0})$fatal(1,"unpack pixel %0d got=%h expected=%h",pcnt,pdata,{source_pixel(pcnt%640,pcnt/640),8'd0});
    pcnt=pcnt+1;
   end
   if(unpack.take && unpack.valid[unpack.write_bank])$fatal(1,"writing a valid unpack bank");
   if(unpack.take && pen&&!pempty && unpack.write_bank==unpack.read_bank)$fatal(1,"unpack bank concurrent read/write");
   if(scan.line_wr_en && scan.line_wr_addr>=640)$fatal(1,"line write overflow");
   if(scan.line_wr_en && scan.rows_mod3!=(scan.rows_loaded%3))$fatal(1,"line bank modulus differs");
   if(scan.line_wr_en && scan.line_ctrl_a[1] && scan.line_ctrl_a[0] && (scan.rows_mod3==scan.rb_top_a || scan.rows_mod3==scan.rb_bot_a))begin
    collisions=collisions+1;$fatal(1,"write to selected scan bank row=%0d sy=%0d x=%0d",scan.rows_loaded,scan.cur_src_y,rawx);
   end
   xd[0]<=rawx;yd[0]<=rawy;for(d=1;d<5;d=d+1)begin xd[d]<=xd[d-1];yd[d]<=yd[d-1];end
   #1;
   if(de)begin
    if(pready)begin expected=expected_pixel(xd[4],yd[4]);ready_pixels=ready_pixels+1;end
    else begin expected=0;starved_pixels=starved_pixels+1;end
    if(rgb!==expected)$fatal(1,"scan RGB x=%0d y=%0d got=%h ref=%h rows=%0d",xd[4],yd[4],rgb,expected,scan.rows_loaded);
    checked=checked+1;
    if(xd[4]==1279&&yd[4]==719)begin frames_checked=frames_checked+1;$display("TRACE: verified 720p frame=%0d pixels=%0d writes=%0d refresh=%0d",frames_checked,checked,writes,refs);end
   end
  end
 end
 integer cyc;
 initial begin
  $timeformat(-9,0,"",0);repeat(40)@(negedge mem);rst=0;wait(ready);repeat(200)@(negedge mem);
  write_frame(460800,230400,0);protect=1;@(negedge video);scan_rst=0;
  fork
   begin for(cyc=0;cyc<8;cyc=cyc+1)write_frame(cyc[0]?1958400:1843200,cyc[1]?28928:115200,32'h25ffe000+cyc);end
   begin wait(frames_checked==6);end
  join
  if(refs<1000 || collisions!=0 || checked<2764800 || starved_pixels<1000 || !injected)$fatal(1,"coverage missing");
  if(!qualified_guard || guarded_cycles<100000 || unsafe_after!=0)$fatal(1,"display-qualified guard not exercised or unsafe entry guard=%b cycles=%0d unsafe=%0d",qualified_guard,guarded_cycles,unsafe_after);
  $display("TRACE: actual display qualification armed guard; guarded_memory_cycles=%0d unsafe_after=%0d",guarded_cycles,unsafe_after);
  $display("PASS: production encrypted SDRAM/FIFO/unpack/scanout with 300us forced midframe starvation and pseudorandom pauses: %0d checked pixels (%0d ready exact RGB, %0d unready correctly black), %0d frames, %0d concurrent writes, %0d refresh; no bright error, unpack-bank or selected-line-bank conflict",checked,ready_pixels,starved_pixels,frames_checked,writes-1,refs);$finish;
 end
 initial begin #160000000;$fatal(1,"native scanout timeout writer=%d reader=%d frame=%d",frames.frame_fifo_write_m0.state,frames.frame_fifo_read_m0.state,frames_checked);end
endmodule


