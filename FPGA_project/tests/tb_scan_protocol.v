`timescale 1ns/1ps
module tb_scan_protocol #(parameter MAP_WRITES=0,STRICT=0,GUARD_ACTIVE=0,POST_GUARD=0);
 reg mem=0,phase=1,net=0,video=0,rst=1;
 always #4 begin mem=~mem;phase=~phase;end
 always #20 net=~net;always #6.666666 video=~video;
 wire ready,refresh,busy,rv,wr,rr;wire [31:0] rd,wd;wire [20:0] wa,ra;wire [3:0] dm;
 wire sclk,ras,cas,we;wire [10:0] adr;wire [1:0] bank;wire [3:0] pins_dm;wire [31:0] dq;
 sdram_pin_model memory(.clk(sclk),.ras(ras),.cas(cas),.we(we),.address(adr),.bank(bank),.dm(pins_dm),.dq(dq));
 sdram ram(.SDRAM_CLK(sclk),.SDR_CKE(),.SDR_RAS(ras),.SDR_CAS(cas),.SDR_WE(we),.SDR_BA(bank),.SDR_ADDR(adr),.SDR_DM(pins_dm),.SDR_DQ(dq),
  .Clk(mem),.Clk_sft(phase),.Rst(rst),.Sdr_init_done(ready),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_wr_en(wr),.App_wr_addr(wa),.App_wr_dm(dm),.App_wr_din(wd),.App_rd_en(rr),.App_rd_addr(ra),.Sdr_rd_en(rv),.Sdr_rd_dout(rd));
 reg wreq=0,wen=0,rreq=0,ren=0;reg [31:0] data=0;reg [20:0] wbase=460800,wlen=230400;
 reg [20:0] rbase=460800,rlen=230400;reg [31:0] expected_seed=32'ha5000000;
 wire wack,wfull,finish,rack,empty;wire [31:0] pixels;
 reg protect=0;
 frame_read_write #(.ENABLE_WRITE_CANCEL(1),.WRITE_V_FLIP(0),.ENABLE_GEOMETRY_GUARD(1)) frames(.geometry_mode(GUARD_ACTIVE!=0 && (!POST_GUARD || protect)),
  .rst(rst),.mem_clk(mem),.Sdr_init_done(ready),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_rd_en(rr),.App_rd_addr(ra),.Sdr_rd_en(rv),.Sdr_rd_dout(rd),.read_clk(video),.read_req(rreq),.read_req_ack(rack),.read_finish(),
  .read_addr_0(rbase),.read_addr_1(21'd0),.read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),.read_len(rlen),.read_en(ren),.read_data(pixels),.read_empty(empty),
  .App_wr_en(wr),.App_wr_addr(wa),.App_wr_din(wd),.App_wr_dm(dm),.write_clk(net),.write_req(wreq),.write_req_ack(wack),.write_finish(finish),
  .write_addr_0(wbase),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),.write_addr_index(2'd0),.write_len(wlen),.write_en(wen),.write_data(data),.write_full(wfull),.write_cancel(1'b0),.write_flip(1'b0));
 integer refs=0,checked=0,cycle;
 always @(posedge sclk)if(ready && {ras,cas,we}==3'b001)refs=refs+1;
 always @(posedge sclk)if(protect && ({ras,cas,we}==3'b100 || memory.write_left!=0))begin
  if(({ras,cas,we}==3'b100 ? memory.index : memory.wp)<1843200)$fatal(1,"map overwrite of immutable cache");
 end
 task write_frame(input integer base,input integer words,input integer seed);integer n;begin
  @(negedge net);wbase=base;wlen=words;wreq=1;wait(wack);@(negedge net);wreq=0;
  repeat(16)@(negedge net);
  for(n=0;n<words;n=n+1)begin
   while(wfull)begin wen=0;@(negedge net);end
   wen=1;data=seed+n;@(negedge net);
  end
  wen=0;wait(finish);repeat(32)@(negedge net);
 end endtask
 task read_frame;integer n;begin
  @(negedge video);rreq=1;wait(rack);@(negedge video);rreq=0;repeat(48)@(negedge video);
  for(n=0;n<rlen;n=n+1)begin
   while(empty)@(negedge video);
   ren=1;@(posedge video);#1;
   if(pixels!==(expected_seed+n))$fatal(1,"full frame word %0d got=%h",n,pixels);
   checked=checked+1;@(negedge video);ren=0;@(negedge video);
  end
 end endtask

 integer ref_pending_during_app=0,pin_ref_during_app=0,issued_words=0,returned_words=0;reg freq_d=0;
 always @(posedge mem)if(ready)begin
  if(rr)issued_words=issued_words+1;if(rv)returned_words=returned_words+1;
  freq_d<=ram.u2_ram.u1_init_ref.Sdr_ref_req;
  if(ram.u2_ram.u1_init_ref.Sdr_ref_req && !freq_d && (rr || wr))ref_pending_during_app=ref_pending_during_app+1;
 end
 integer wide_acks=0,unsafe_read_entries=0,fifo_overflows=0,steady_ref_during_app=0;reg ack_d=0,entry_unsafe=0;
 always @(posedge sclk)if(protect && {ras,cas,we}==3'b001 && (rr || wr))steady_ref_during_app=steady_ref_during_app+1;
 always @(posedge mem)if(ready)begin
  ack_d<=ram.u2_ram.u1_init_ref.Sdr_ref_ack;
  if(ram.u2_ram.u1_init_ref.Sdr_ref_ack && ack_d)begin
   wide_acks=wide_acks+1;
   if(wide_acks<=3)$display("ACK_LEVEL: two-cycle refresh ACK at time=%0t guard=%0d",$time,GUARD_ACTIVE);
  end
  entry_unsafe=frames.frame_fifo_read_m0.state==2 && (busy || refresh);
  if(rv && frames.read_buf.full_flag)fifo_overflows=fifo_overflows+1;
  #1;if(entry_unsafe && frames.frame_fifo_read_m0.state==3)unsafe_read_entries=unsafe_read_entries+1;
 end
 integer steady_violations=0;
 integer scycle=0,last_ref=-100000,first_ref=-1,rfcs=0,violations=0,min_gap=100000,min_ref_act=100000,min_act_rd=100000;
 integer last_act[0:3],last_act_same[0:3],min_act_same=100000,max_ref_gap=0,min_ref_gap=100000,mb;
 initial for(mb=0;mb<4;mb=mb+1)begin last_act[mb]=-100000;last_act_same[mb]=-100000;end
 always @(posedge sclk)begin
  scycle=scycle+1;
  if(ready && {ras,cas,we}!=3'b111)begin
   if({ras,cas,we}==3'b011 || {ras,cas,we}==3'b101 || {ras,cas,we}==3'b100 || {ras,cas,we}==3'b001)begin
    if(scycle-last_ref<min_gap)min_gap=scycle-last_ref;
    if(scycle-last_ref<8)begin
     violations=violations+1;
     if(protect)steady_violations=steady_violations+1;
     if(violations<=6)$display("VIOLATION: tRFC cycle=%0d cmd=%b elapsed_cycles=%0d elapsed_ns=%0d busy=%b refresh_vld=%b app_rd=%b app_wr=%b",scycle,{ras,cas,we},scycle-last_ref,(scycle-last_ref)*8,busy,refresh,rr,wr);
    end
   end
   if({ras,cas,we}==3'b001)begin
    if(rr || wr)pin_ref_during_app=pin_ref_during_app+1;
    if(first_ref<0)first_ref=scycle;
    else begin
     if(scycle-last_ref<min_ref_gap)min_ref_gap=scycle-last_ref;
     if(scycle-last_ref>max_ref_gap)max_ref_gap=scycle-last_ref;
    end
    last_ref=scycle;rfcs=rfcs+1;
   end
   if({ras,cas,we}==3'b011)begin
    if(scycle-last_ref<min_ref_act)min_ref_act=scycle-last_ref;
    if(scycle-last_act_same[bank]<min_act_same)min_act_same=scycle-last_act_same[bank];
    last_act[bank]=scycle;last_act_same[bank]=scycle;
   end
   if({ras,cas,we}==3'b101 && scycle-last_act[bank]<min_act_rd)min_act_rd=scycle-last_act[bank];
  end
 end
 initial begin
  $timeformat(-9,0,"",0);repeat(40)@(negedge mem);rst=0;wait(ready);repeat(200)@(negedge mem);
  write_frame(460800,230400,32'ha5000000);protect=1;
  fork
   begin if(MAP_WRITES)for(cycle=0;cycle<10;cycle=cycle+1)write_frame(cycle[0]?1958400:1843200,115200,32'h25ffe000+cycle);end
   begin repeat(3)read_frame;end
  join
  read_frame;
  if(MAP_WRITES)begin
   rbase=1843200;rlen=115200;expected_seed=32'h25ffe008;read_frame;
   rbase=1958400;rlen=115200;expected_seed=32'h25ffe009;read_frame;
  end
  if(refs<1000)$fatal(1,"refresh not exercised");
  $display("MEASURE: map_writes=%0d checked_words=%0d tRFC_violations=%0d min_REF_CMD_cycles=%0d min_REF_ACT_cycles=%0d min_ACT_RD_cycles=%0d min_same_bank_ACT_cycles=%0d refs=%0d min_ref_gap_cycles=%0d max_ref_gap_cycles=%0d average_ref_gap_cycles=%0f",MAP_WRITES,checked,violations,min_gap,min_ref_act,min_act_rd,min_act_same,rfcs,min_ref_gap,max_ref_gap,1.0*(last_ref-first_ref)/(rfcs-1));
  $display("MEASURE: steady_after_initial_cache_tRFC_violations=%0d",steady_violations);
  $display("MEASURE: issued_words=%0d returned_words=%0d refresh_requested_during_app=%0d physical_refresh_while_app=%0d",issued_words,returned_words,ref_pending_during_app,pin_ref_during_app);
  $display("MEASURE: guard=%0d wide_refresh_ACK=%0d unsafe_read_entries=%0d FIFO_overflows=%0d steady_ref_during_app=%0d",GUARD_ACTIVE,wide_acks,unsafe_read_entries,fifo_overflows,steady_ref_during_app);
  if(STRICT && violations!=0)$fatal(1,"tRFC requires at least 8 cycles (63ns EM638325 slowest listed speed), found %0d violations",violations);
  if(issued_words!=returned_words)$fatal(1,"commands dropped");
  if(!POST_GUARD && pin_ref_during_app!=0)$fatal(1,"commands dropped or refresh collided with input App burst");
  if(POST_GUARD && (steady_ref_during_app!=0 || steady_violations!=0 || unsafe_read_entries!=0))$fatal(1,"post-qualification protocol violation");
  $display("PASS: native encrypted SDRAM + real asynchronous FIFOs, four 230400-word photo reads plus final two 115200-word map reads when enabled (%0d words), %0d complete 115200-word map writes, refreshes=%0d, no cache overwrite",checked,MAP_WRITES?10:0,refs);$finish;
 end
 initial begin #120000000;$fatal(1,"native frame timeout writer=%d reader=%d",frames.frame_fifo_write_m0.state,frames.frame_fifo_read_m0.state);end
endmodule
