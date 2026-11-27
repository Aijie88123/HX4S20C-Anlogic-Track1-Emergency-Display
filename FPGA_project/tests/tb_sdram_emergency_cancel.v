`timescale 1ns/1ps
module tb_sdram_emergency_cancel;
 reg mem=0,phase=1,net=0,video=0,rst=1;
 always #4 begin mem=~mem;phase=~phase;end
 always #20 net=~net;always #6.666666 video=~video;
 wire ready,refresh,busy,rv,wr,rr;wire [31:0] rd,wd;wire [20:0] wa,ra;wire [3:0] dm;
 wire sclk,ras,cas,we;wire [10:0] adr;wire [1:0] bank;wire [3:0] pins_dm;wire [31:0] dq;
 sdram_pin_model memory(.clk(sclk),.ras(ras),.cas(cas),.we(we),.address(adr),.bank(bank),.dm(pins_dm),.dq(dq));
 sdram ram(.SDRAM_CLK(sclk),.SDR_CKE(),.SDR_RAS(ras),.SDR_CAS(cas),.SDR_WE(we),.SDR_BA(bank),.SDR_ADDR(adr),.SDR_DM(pins_dm),.SDR_DQ(dq),
  .Clk(mem),.Clk_sft(phase),.Rst(rst),.Sdr_init_done(ready),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_wr_en(wr),.App_wr_addr(wa),.App_wr_dm(dm),.App_wr_din(wd),.App_rd_en(rr),.App_rd_addr(ra),.Sdr_rd_en(rv),.Sdr_rd_dout(rd));
 reg wreq=0,wen=0,cancel=0,rreq=0,ren=0;reg [31:0] data=32'h25ffe01f;
 wire wack,wfull,finish,rack,empty;wire [31:0] pixels;
 frame_read_write #(.ENABLE_WRITE_CANCEL(1),.WRITE_V_FLIP(0)) frames(
  .rst(rst),.mem_clk(mem),.Sdr_init_done(ready),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_rd_en(rr),.App_rd_addr(ra),.Sdr_rd_en(rv),.Sdr_rd_dout(rd),.read_clk(video),.read_req(rreq),.read_req_ack(rack),.read_finish(),
  .read_addr_0(21'd460800),.read_addr_1(21'd0),.read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),.read_len(21'd230400),.read_en(ren),.read_data(pixels),.read_empty(empty),
  .App_wr_en(wr),.App_wr_addr(wa),.App_wr_din(wd),.App_wr_dm(dm),.write_clk(net),.write_req(wreq),.write_req_ack(wack),.write_finish(finish),
  .write_addr_0(21'd1843200),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),.write_addr_index(2'd0),.write_len(21'd115200),.write_en(wen),.write_data(data),.write_full(wfull),.write_cancel(cancel));
 integer n,k,p,corrupt=0,commands=0,refs=0;reg check=0;
 always @(posedge sclk)if(check && {ras,cas,we}==3'b001)refs=refs+1;
 always @(posedge sclk)if(check && ({ras,cas,we}==3'b100 || memory.write_left!=0))begin
  if(({ras,cas,we}==3'b100 ? memory.index : memory.wp)<1843200)begin
   corrupt=corrupt+1;
   if(corrupt<8)$display("CORRUPT time=%t physical=%h cmd=%b data=%h app=%b logical=%h cancel=%b state=%d",$time,
    {ras,cas,we}==3'b100 ? memory.index : memory.wp,{ras,cas,we},dq,wr,wa,cancel,frames.frame_fifo_write_m0.state);
  end
  commands=commands+1;
 end
 initial begin
  repeat(40)@(negedge mem);rst=0;wait(ready);repeat(200)@(negedge mem);check=1;
  fork
   begin
    @(negedge video);rreq=1;wait(rack);@(negedge video);rreq=0;
    forever begin @(negedge video);ren=!empty;end
   end
   begin
    // Aborts at every offset through a write burst, as mode changes or
    // replacement metadata can cancel the live renderer's current frame.
    for(p=0;p<32;p=p+1)begin
     @(negedge net);wreq=1;wait(wack);@(negedge net);wreq=0;repeat(16)@(negedge net);
     for(n=0;n<300;n=n+1)begin wen=1;@(negedge net);end
     wen=0;wait(wr);repeat(p)@(negedge mem);cancel=1;
     repeat(8)@(negedge net);cancel=0;repeat(40)@(negedge net);
    end
    if(corrupt!=0)$fatal(1,"FAIL: %d renderer words wrote into immutable image regions across 32 cancellations",corrupt);
    $display("PASS: %d command-level renderer writes stay outside immutable images through 32 burst abort positions; refreshes=%d",commands,refs);$finish;
   end
  join
 end
 initial begin #20000000;$fatal(1,"cancel test timeout");end
endmodule
