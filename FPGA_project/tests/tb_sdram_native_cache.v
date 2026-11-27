`timescale 1ns/1ps
module tb_sdram_native_cache;
 reg clk=0,phase=0,rst=1;always #4 clk=~clk;initial begin #2;forever #4 phase=~phase;end
 wire sclk,ras,cas,we;wire [10:0] adr;wire [1:0] bank;wire [3:0] dm;wire [31:0] dq;
 sdram_pin_model memory(.clk(sclk),.ras(ras),.cas(cas),.we(we),.address(adr),.bank(bank),.dm(dm),.dq(dq));
 wire ready,refresh,busy,rv;wire [31:0] rd;
 reg wr=0,rr=0;reg [20:0] wa=0,ra=0;reg [31:0] wd=0;
 sdram dut(.SDRAM_CLK(sclk),.SDR_CKE(),.SDR_RAS(ras),.SDR_CAS(cas),.SDR_WE(we),.SDR_BA(bank),.SDR_ADDR(adr),.SDR_DM(dm),.SDR_DQ(dq),
  .Clk(clk),.Clk_sft(phase),.Rst(rst),.Sdr_init_done(ready),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_wr_en(wr),.App_wr_addr(wa),.App_wr_dm(4'b0),.App_wr_din(wd),.App_rd_en(rr),.App_rd_addr(ra),.Sdr_rd_en(rv),.Sdr_rd_dout(rd));
 integer n,count=0,refs=0;
 always @(posedge sclk)if(ready && {ras,cas,we}==3'b001)refs=refs+1;
 integer cmds=0;
 always @(posedge sclk)if(ready && {ras,cas,we}!=3'b111 && cmds<40)begin
  $display("CMD %t %b bank=%h address=%h dq=%h appwr=%b wa=%h busy=%b refresh=%b",$time,{ras,cas,we},bank,adr,dq,wr,wa,busy,refresh);cmds=cmds+1;
 end
 always @(posedge clk)if(rv)begin
  if(rd!==(32'h12340000+count))$fatal(1,"native SDRAM mismatch word=%d got=%h",count,rd);
  count=count+1;
 end
 initial begin
  repeat(40)@(negedge clk);rst=0;wait(ready);repeat(200)@(negedge clk);
  for(n=0;n<256;n=n+1)begin wr=1;wa=21'd460800+n;wd=32'h12340000+n;@(negedge clk);end
  wr=0;repeat(100)@(negedge clk);
  for(n=0;n<256;n=n+1)begin rr=1;ra=21'd460800+n;@(negedge clk);end
  rr=0;repeat(200)@(negedge clk);
  if(count!=256)$fatal(1,"native SDRAM received %d",count);
  repeat(40000)@(negedge clk);
  $display("MEASURE: automatic refresh refs=%d busy=%b refresh_vld=%b",refs,busy,refresh);
  if(refs<8)$fatal(1,"automatic refresh missing");
  $display("PASS: production encrypted SDRAM controller with independent BL4 CL3 pin model, 256 words, idle refresh commands=%d",refs);$finish;
 end
 initial begin #3000000;$fatal(1,"native SDRAM timeout");end
endmodule
