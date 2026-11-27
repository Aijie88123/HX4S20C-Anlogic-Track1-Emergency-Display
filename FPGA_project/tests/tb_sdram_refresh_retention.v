`timescale 1ns/1ps
`include "global_def.v"
module tb_sdram_refresh_retention #(parameter EXPECT_REFRESH=1);
 reg clk=0,phase=1,rst=1;always #4 begin clk=~clk;phase=~phase;end
 wire sclk,ras,cas,we;wire [10:0] adr;wire [1:0] bank;wire [3:0] dm;wire [31:0] dq;
 wire ready,refresh,busy,rv;wire [31:0] rd;
 reg wr=0,rr=0;reg [20:0] wa=0,ra=0;reg [31:0] wd=0;
 sdram_pin_model memory(.clk(sclk),.ras(ras),.cas(cas),.we(we),.address(adr),.bank(bank),.dm(dm),.dq(dq));
 sdram dut(.SDRAM_CLK(sclk),.SDR_CKE(),.SDR_RAS(ras),.SDR_CAS(cas),.SDR_WE(we),.SDR_BA(bank),.SDR_ADDR(adr),.SDR_DM(dm),.SDR_DQ(dq),
  .Clk(clk),.Clk_sft(phase),.Rst(rst),.Sdr_init_done(ready),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
  .App_wr_en(wr),.App_wr_addr(wa),.App_wr_dm(4'd0),.App_wr_din(wd),.App_rd_en(rr),.App_rd_addr(ra),.Sdr_rd_en(rv),.Sdr_rd_dout(rd));
 integer refs=0,refresh_rows=0,checked=0,received=0,n,role,cycle,j;
 integer expected_role=0;reg verify=0,protect=0;
 reg [2047:0] covered=0;time last_refresh=0,max_gap=0,started,max_row_gap=0;
 time row_refreshed[0:2047];integer row_number;
 initial for(row_number=0;row_number<2048;row_number=row_number+1)row_refreshed[row_number]=0;
 always @(posedge sclk)if(ready && {ras,cas,we}==3'b001)begin
  if(last_refresh!=0 && $time-last_refresh>max_gap)max_gap=$time-last_refresh;
  if(row_refreshed[refresh_rows]!=0 && $time-row_refreshed[refresh_rows]>max_row_gap)max_row_gap=$time-row_refreshed[refresh_rows];
  row_refreshed[refresh_rows]=$time;
  last_refresh=$time;covered[refresh_rows]=1;refresh_rows=(refresh_rows+1)%2048;refs=refs+1;
 end
 always @(posedge sclk)if(protect && ({ras,cas,we}==3'b100 || memory.write_left!=0))begin
  if(({ras,cas,we}==3'b100 ? memory.index : memory.wp)<1843200)$fatal(1,"map write escaped reserved region");
 end
 always @(posedge clk)if(rv && verify)begin
  if(rd!==(32'ha5000000|(expected_role<<16)|received))$fatal(1,"cached image changed role=%0d word=%0d got=%h",expected_role,received,rd);
  received=received+1;checked=checked+1;
 end
 task write_block(input integer base,input integer seed);begin
  wait(!busy);repeat(20)@(negedge clk);
  for(j=0;j<256;j=j+1)begin wr=1;wa=base+j;wd=seed|j;@(negedge clk);end
  wr=0;repeat(32)@(negedge clk);
 end endtask
 task read_cache(input integer selected);begin
  wait(!busy);repeat(20)@(negedge clk);expected_role=selected;received=0;verify=1;
  for(j=0;j<256;j=j+1)begin rr=1;ra=selected*230400+j;@(negedge clk);end
  rr=0;repeat(32)@(negedge clk);verify=0;
  if(received!=256)$fatal(1,"native read dropped words %0d",received);
 end endtask
 initial begin
  $timeformat(-9,0,"",0);
  $display("MEASURE: macro clock_ns=%0d refresh_interval=%0d",`SDR_CLK_PERIOD,`SELF_REFRESH_INTERVAL);
  if((EXPECT_REFRESH && `SELF_REFRESH_INTERVAL!=1953)||(!EXPECT_REFRESH && `SELF_REFRESH_INTERVAL!=0))$fatal(1,"unexpected macro constant");
  repeat(40)@(negedge clk);rst=0;wait(ready);repeat(200)@(negedge clk);
  for(role=0;role<8;role=role+1)write_block(role*230400,32'ha5000000|(role<<16));
  protect=1;started=$time;
  for(cycle=0;cycle<32;cycle=cycle+1)begin
   // Alternate actual native accesses to the map/particle reservations,
   // then return to one of the immutable image slots, across >64 ms.
   for(n=0;n<64;n=n+1)write_block((cycle[0]?1958400:1843200)+n*256,32'h01230000|(cycle<<8));
   read_cache(cycle%8);
   repeat(300000)@(negedge clk);
  end
  for(role=0;role<8;role=role+1)read_cache(role);
  if(EXPECT_REFRESH)begin
   if(refs<4096 || covered!={2048{1'b1}} || max_gap>40000 || max_row_gap>64000000)$fatal(1,"refresh coverage failure refs=%0d max_gap_ns=%0t row_gap_ns=%0t",refs,max_gap,max_row_gap);
  end else if(refs!=0)$fatal(1,"baseline refresh unexpectedly occurred");
  $display("PASS: expected_refresh=%0d changes=32 elapsed_ns=%0t native_cache_words=%0d refreshes=%0d max_gap_ns=%0t max_row_gap_ns=%0t all_rows=%b",EXPECT_REFRESH,$time-started,checked,refs,max_gap,max_row_gap,&covered);$finish;
 end
 initial begin #150000000;$fatal(1,"retention regression timeout");end
endmodule
