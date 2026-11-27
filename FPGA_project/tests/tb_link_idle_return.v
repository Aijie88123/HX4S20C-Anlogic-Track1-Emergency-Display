`timescale 1ns/1ps
module sys_pll(input refclk,reset,output reg clk0_out=0,clk1_out=0,clk2_out=1,extlock=0);
 always #10 clk0_out=~clk0_out;always #4 begin clk1_out=~clk1_out;clk2_out=~clk2_out;end
 initial #400 extlock=1;
endmodule
module sdram(input Clk,Clk_sft,Rst,output reg Sdr_init_done=0,output Sdr_init_ref_vld,Sdr_busy,
 input App_wr_en,input [20:0] App_wr_addr,input [3:0] App_wr_dm,input [31:0] App_wr_din,
 input App_rd_en,input [20:0] App_rd_addr,output reg Sdr_rd_en=0,output reg [31:0] Sdr_rd_dout=0);
 reg [31:0] ram[0:2097151];integer writes=0,init_count=0;
 assign Sdr_init_ref_vld=0;assign Sdr_busy=0;
 always @(posedge Clk)begin
  if(Rst)begin init_count<=0;Sdr_init_done<=0;Sdr_rd_en<=0;end
  else begin
   if(init_count<32)init_count<=init_count+1;else Sdr_init_done<=1;
   Sdr_rd_en<=App_rd_en;if(App_rd_en)Sdr_rd_dout<=ram[App_rd_addr];
   if(App_wr_en)begin
    if(App_wr_addr>=1843200)$fatal(1,"FAIL: cache address exceeds six-image region");
    ram[App_wr_addr]<=App_wr_din;writes<=writes+1;
   end
  end
 end
endmodule
module tb_link_idle_return #(parameter FULL_IMAGES=0,INJECT_FAULTS=0,PULSE_CYCLES=1,EXPECT_OLD_ABORT=0);
 reg clk=0,net_clk=0,rst_n=0,request=0,read_enable=0,priority_emergency=0;
 always #10 clk=~clk;always #20 net_clk=~net_clk;
 reg [2:0] role=2;wire read_ack,read_empty;wire [31:0] read_data;
 wire [5:0] available;wire [191:0] sizes;wire [3:0] fault;wire recurring;
 b_media_storage #(.CLK_FREQ_HZ(1000000),.REMOTE_TF(0),.IMAGE_ROLES(6),.NUMBERED_SIX(1),
  .EMERGENCY_PRIORITY(1),.SCAN_RETRY_MS(10),.BAD_RETRY_MS(60),.INIT_TIMEOUT_MS(200)) dut(
  .clk(clk),.rst_n(rst_n),.net_clk(net_clk),.net_rst(!rst_n),.sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi(),
  .online(1'b1),.packet_valid(1'b0),.packet(224'd0),.tf_stream_valid(),.tf_stream_data(),.tf_stream_ready(1'b1),
  .read_req(request),.read_en(read_enable),.read_role(role),.priority_emergency(priority_emergency),
  .map_write_req(1'b0),.map_write_en(1'b0),.map_write_cancel(1'b0),.map_write_data(32'd0),
  .map_write_ack(),.map_write_full(),.map_write_done_toggle(),.render_clk(),.render_rst(),
  .read_ack(read_ack),.read_empty(read_empty),.read_data(read_data),.available(available),.source_sizes(sizes),
  .source_fault(fault),.source_fault_recurring(recurring));
 defparam dut.local_tf.sd_card_top_m0.spi_master_m0.FULL_IMAGES=FULL_IMAGES;
 reg [31:0] expected[0:1843199],expected_sizes[0:5];
 initial begin
  $readmemh(FULL_IMAGES?"storage_recovery_vectors/full_expected.hex":"storage_recovery_vectors/small_expected.hex",expected);
  $readmemh(FULL_IMAGES?"storage_recovery_vectors/full_sizes.hex":"storage_recovery_vectors/small_sizes.hex",expected_sizes);
 end

 reg injected_idle=0;
 initial begin
  wait(rst_n && dut.state==4 && dut.started && dut.bmp_read_m0.state==16);
  @(negedge dut.sd_clk);injected_idle=1;
  force dut.parser_ready=1'b1;
  repeat(PULSE_CYCLES)@(negedge dut.sd_clk);
  release dut.parser_ready;
  if(EXPECT_OLD_ABORT)begin
   wait(dut.fault!=0);#1;
   if(dut.fault!=2 || dut.failed_debug[19:0]!=0 || dut.failed_debug[31:20]!=0)
    $fatal(1,"FAIL: old pre-pixel abort not reproduced fault=%h debug=%h",dut.fault,dut.failed_debug);
   $display("PASS: reproduced R5 fault2 and zero pixel-phase bytes by a short false idle during CHAIN_WAIT, pulse=%0d",PULSE_CYCLES);$finish;
  end
 end
 always @(posedge dut.sd_clk)if(rst_n && injected_idle && !EXPECT_OLD_ABORT && dut.fault!=0)
  $fatal(1,"FAIL: short idle canceled live load pulse=%0d fault=%h stage=%0d",PULSE_CYCLES,dut.fault,dut.bmp_read_m0.state);
 integer observed_initialization_fault=0,observed_scan_failure=0,observed_bad_round=0;
 integer cache_count=0,load_order[0:5],last_role=7;reg [5:0] previous_cache=0;
 reg corrupt_source=INJECT_FAULTS;
 always @(negedge dut.sd_clk)if(rst_n)begin
  dut.local_tf.sd_card_top_m0.spi_master_m0.bad_source_header=corrupt_source&&dut.state==4&&dut.loading_role==3;
  if(INJECT_FAULTS && fault==5)begin
   if(!observed_initialization_fault)$display("INIT recovery at %t state=%d counter=%d",$time,dut.state,dut.recovery_count);
   observed_initialization_fault=1;dut.local_tf.sd_card_top_m0.spi_master_m0.hold_init=0;
  end
  if(INJECT_FAULTS && fault==6&&dut.found_mask==0)begin
   if(!observed_scan_failure)$display("SCAN recovery at %t state=%d",$time,dut.state);
   observed_scan_failure=1;
  end
  if(INJECT_FAULTS && dut.state==5 && dut.bad_backoff && dut.failed_mask[3])begin
   observed_bad_round=1;corrupt_source=0;
   if(dut.cache_mask!==6'b110111)$fatal(1,"FAIL: completed source cache lost across bad-source retries: %b",dut.cache_mask);
  end
  if((dut.cache_mask&previous_cache)!==previous_cache)$fatal(1,"FAIL: complete cache invalidated by partial scan");
  if(dut.cache_mask!=previous_cache)begin
   for(integer k=0;k<6;k=k+1)if(dut.cache_mask[k]&&!previous_cache[k])begin
    load_order[cache_count]=k;cache_count=cache_count+1;
    $display("CACHE role=%d mask=%b at %t",k,dut.cache_mask,$time);
   end
   previous_cache=dut.cache_mask;
  end
  if(dut.state==4&&dut.loading_role==2)priority_emergency=1;
 end
 initial begin
  #1000000;$display("DEBUG 1ms storage=%d parser=%d card=%d ready=%b rst=%b rec=%d fault=%d reads=%d",dut.state,dut.bmp_read_m0.state,dut.local_tf.sd_card_top_m0.sd_card_sec_read_write_m0.state,dut.sd_ready,dut.sd_rst,dut.recovery_count,fault,dut.local_tf.sd_card_top_m0.spi_master_m0.reads);
 end
 integer which,index,checked=0,reads_before;
 initial begin
  dut.local_tf.sd_card_top_m0.spi_master_m0.hold_init=INJECT_FAULTS;
  dut.local_tf.sd_card_top_m0.spi_master_m0.fail_first_scan=INJECT_FAULTS;
  repeat(20)@(negedge net_clk);rst_n=1;
  wait(available==63);repeat(30)@(negedge net_clk);
  if(cache_count!=6||load_order[0]!=2||load_order[1]!=0||load_order[2]!=1)$fatal(1,"FAIL: emergency preparation did not follow current load: %d %d %d",load_order[0],load_order[1],load_order[2]);
  if(INJECT_FAULTS&&(!observed_initialization_fault||!observed_scan_failure||!observed_bad_round||!recurring))
   $fatal(1,"FAIL: fault/recovery scenario not exercised init=%d scan=%d bad=%d recurring=%b",observed_initialization_fault,observed_scan_failure,observed_bad_round,recurring);
  if(fault!=0)$fatal(1,"FAIL: recovered source fault not cleared");
  reads_before=dut.local_tf.sd_card_top_m0.spi_master_m0.reads;
  for(which=0;which<6;which=which+1)begin
   role=which;if(sizes[which*32+:32]!==expected_sizes[which])$fatal(1,"FAIL: source size metadata role %d",which);
   request=1;wait(read_ack);@(negedge net_clk);request=0;repeat(8)@(negedge net_clk);
   for(index=0;index<307200;index=index+1)begin
    while(read_empty)@(negedge net_clk);
    read_enable=1;@(negedge net_clk);read_enable=0;
    if(read_data!==expected[which*307200+index])$fatal(1,"FAIL: RAM/FIFO normalized pixel role=%d index=%d got=%h expected=%h",which,index,read_data,expected[which*307200+index]);
    checked=checked+1;@(negedge net_clk);
   end
   repeat(10)@(negedge net_clk);
  end
  if(dut.local_tf.sd_card_top_m0.spi_master_m0.reads!=reads_before)$fatal(1,"FAIL: fully cached source kept scanning TF card");
  if(FULL_IMAGES)$display("PASS: six actual saved BMPs, 640x480 and 800x600 06; fragmented 8-sector FAT32 clusters, real BMP/scaler/FIFO/RAM and %0d independently checked normalized pixels; 05/06 priority after current source; no rescan after complete cache",checked);
  else $display("PASS: R6 ignores a short false idle at the pre-pixel FAT transition; six complete normalized frames and %0d independently checked pixels",checked);
  $finish;
 end
 initial begin #3000000000;$fatal(1,"FAIL: storage recovery timeout state=%d cache=%b found=%b failed=%b fault=%d",dut.state,dut.cache_mask,dut.found_mask,dut.failed_mask,fault);end
endmodule
