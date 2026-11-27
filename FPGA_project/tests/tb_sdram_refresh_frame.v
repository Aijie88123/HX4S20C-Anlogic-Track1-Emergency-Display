`timescale 1ns/1ps
module tb_sdram_refresh_frame;
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
 wire wack,wfull,finish,rack,empty;wire [31:0] pixels;
 frame_read_write #(.ENABLE_WRITE_CANCEL(1),.WRITE_V_FLIP(0)) frames(
  .rst(rst),.mem_clk(mem),.Sdr_init_done(ready),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_rd_en(rr),.App_rd_addr(ra),.Sdr_rd_en(rv),.Sdr_rd_dout(rd),.read_clk(video),.read_req(rreq),.read_req_ack(rack),.read_finish(),
  .read_addr_0(21'd460800),.read_addr_1(21'd0),.read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),.read_len(21'd230400),.read_en(ren),.read_data(pixels),.read_empty(empty),
  .App_wr_en(wr),.App_wr_addr(wa),.App_wr_din(wd),.App_wr_dm(dm),.write_clk(net),.write_req(wreq),.write_req_ack(wack),.write_finish(finish),
  .write_addr_0(wbase),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),.write_addr_index(2'd0),.write_len(wlen),.write_en(wen),.write_data(data),.write_full(wfull),.write_cancel(1'b0),.write_flip(1'b0));
 integer refs=0,checked=0,cycle;reg protect=0;
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
  for(n=0;n<230400;n=n+1)begin
   while(empty)@(negedge video);
   ren=1;@(posedge video);#1;
   if(pixels!==(32'ha5000000+n))$fatal(1,"full frame word %0d got=%h",n,pixels);
   checked=checked+1;@(negedge video);ren=0;@(negedge video);
  end
 end endtask
 initial begin
  $timeformat(-9,0,"",0);repeat(40)@(negedge mem);rst=0;wait(ready);repeat(200)@(negedge mem);
  write_frame(460800,230400,32'ha5000000);protect=1;
  fork
   begin for(cycle=0;cycle<10;cycle=cycle+1)write_frame(cycle[0]?1958400:1843200,cycle[1]?28928:115200,32'h25ffe000+cycle);end
   begin read_frame;read_frame;read_frame;end
  join
  read_frame;
  if(refs<1000)$fatal(1,"refresh not exercised");
  $display("PASS: native encrypted SDRAM + real asynchronous FIFOs, full 230400-word RGB888 image read four times (%0d words), 10 interleaved full map/particle frame writes, refreshes=%0d, no cache overwrite",checked,refs);$finish;
 end
 initial begin #100000000;$fatal(1,"native frame timeout writer=%d reader=%d",frames.frame_fifo_write_m0.state,frames.frame_fifo_read_m0.state);end
endmodule
