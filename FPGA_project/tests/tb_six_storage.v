`timescale 1ns/1ps
// Only PLL pins and the physical memory are modeled. Parser, scaler, FIFOs,
// SDRAM request arbitration and frame completion are the production RTL.
module sys_pll(input refclk,reset,output reg clk0_out=0,clk1_out=0,clk2_out=1,extlock=0);
 always #10 clk0_out=~clk0_out;always #4 begin clk1_out=~clk1_out;clk2_out=~clk2_out;end
 initial #400 extlock=1;
endmodule
module sdram(input Clk,Clk_sft,Rst,output reg Sdr_init_done=0,output Sdr_init_ref_vld,Sdr_busy,
 input App_wr_en,input [20:0] App_wr_addr,input [3:0] App_wr_dm,input [31:0] App_wr_din,
 input App_rd_en,input [20:0] App_rd_addr,output reg Sdr_rd_en=0,output reg [31:0] Sdr_rd_dout=0);
 reg [31:0] ram[0:2097151];integer writes=0;integer init_count=0;
 assign Sdr_init_ref_vld=0;assign Sdr_busy=0;
 always @(posedge Clk)begin
  if(Rst)begin init_count<=0;Sdr_init_done<=0;Sdr_rd_en<=0;end
  else begin
   if(init_count<32)init_count<=init_count+1;else Sdr_init_done<=1;
   Sdr_rd_en<=App_rd_en;if(App_rd_en)Sdr_rd_dout<=ram[App_rd_addr];
   if(App_wr_en)begin if(App_wr_addr>=1843200)$fatal(1,"FAIL: B compact source cache address");ram[App_wr_addr]<=App_wr_din;writes<=writes+1;end
  end
 end
endmodule
module tb_six_storage #(parameter MISSING_TWO=0,FULL_IMAGES=0,STALL=0);
 reg aclk=0;always #5 aclk=~aclk;
 reg clk=0,net_clk=0,rst_n=0,req=0,en=0;reg [2:0] role=2;reg [1:0] readstate=0;
 always #10 clk=~clk;always #20 net_clk=~net_clk;
 wire ack,empty;wire [31:0] data;wire [5:0] available;wire [191:0] sizes;wire [3:0] fault;
 wire av,bv;wire [223:0] ap,bp;reg pa=0,pb=0;reg [223:0] ppa=0,ppb=0;
 reg [223:0] ahold,bhold;integer aflight=0,bflight=0,agap=0,bgap=0;
 wire ar=aflight==0&&agap==0,br=bflight==0&&bgap==0;
 a_tf_sector_service #(.SD_CLK_HZ(1000000)) a_reader(.sd_clk(aclk),.net_clk(net_clk),.rst(!rst_n),.online(1'b1),
  .packet_valid(pa),.packet(ppa),.stream_valid(av),.stream_data(ap),.stream_ready(ar),.sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi());
 always @(posedge net_clk)begin
  pa<=0;pb<=0;
  if(agap!=0)agap<=agap-1;if(bgap!=0)bgap<=bgap-1;
  if(av&&ar)begin ahold<=ap;aflight<=144;agap<=169;end
  if(bv&&br)begin bhold<=bp;bflight<=144;bgap<=169;end
  if(aflight!=0)begin aflight<=aflight-1;if(aflight==1)begin pb<=1;ppb<=ahold;end end
  if(bflight!=0)begin bflight<=bflight-1;if(bflight==1)begin pa<=1;ppa<=bhold;end end
 end
 b_media_storage #(.CLK_FREQ_HZ(1000000),.REMOTE_TF(1),.IMAGE_ROLES(6),.NUMBERED_SIX(1)) dut(.clk(clk),.rst_n(rst_n),.net_clk(net_clk),.net_rst(!rst_n),
  .sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi(),
  .online(1'b1),.packet_valid(pb),.packet(ppb),.tf_stream_valid(bv),.tf_stream_data(bp),.tf_stream_ready(br),.read_req(req),.read_en(en),.read_role(role),
  .read_ack(ack),.read_empty(empty),.read_data(data),.available(available),.source_sizes(sizes),.source_fault(fault),.source_fault_recurring());
 defparam a_reader.sd_card_top_m0.spi_master_m0.FULL_IMAGES=FULL_IMAGES;
 reg stall_triggered=0,stall_recovered=0;
 always @(negedge net_clk)if(STALL)begin
  if(!stall_triggered && dut.loading_role==3 && dut.state==4 && dut.U3.writes>616448)begin
   a_reader.sd_card_top_m0.spi_master_m0.pause_transport=1;stall_triggered=1;
  end
  if(stall_triggered && !stall_recovered && fault!=0)begin
   if(dut.cache_mask[2:0]!=5 || dut.cache_mask[3])$fatal(1,"FAIL: partial source replaced prior complete cache");
   a_reader.sd_card_top_m0.spi_master_m0.pause_transport=0;stall_recovered=1;
  end
 end
 integer debug_reads=0,debug_bytes=0;reg [2:0] prior_state=0;reg [7:0] debug_expected;integer scan_end_checks=0;
 always @(posedge aclk)if(a_reader.sd_req)begin debug_reads=debug_reads+1;if(debug_reads<30)$display("DEBUG A read=%d LBA=%d",debug_reads,a_reader.sd_address);end
 always @(negedge dut.sd_clk)begin
  if(dut.byte_valid)begin
   debug_expected=a_reader.sd_card_top_m0.spi_master_m0.disk[a_reader.sd_address*512+debug_bytes];
   if(MISSING_TWO&&a_reader.sd_address==514+a_reader.sd_card_top_m0.spi_master_m0.starts[2]-2&&debug_bytes==26)debug_expected=2;
   if(dut.byte_data!==debug_expected)$fatal(1,"FAIL B byte=%d addr=%d actual=%h expected=%h",debug_bytes,a_reader.sd_address,dut.byte_data,a_reader.sd_card_top_m0.spi_master_m0.disk[a_reader.sd_address*512+debug_bytes]);
   debug_bytes=debug_bytes+1;
  end
  if(dut.sec_end)begin if(debug_reads<30)$display("DEBUG B end bytes=%d parser=%d found=%b",debug_bytes,dut.bmp_read_m0.state,dut.found_mask);debug_bytes=0;end
  if(dut.scan_done&&scan_end_checks==0)begin scan_end_checks=scan_end_checks+1;$display("DEBUG scan done found=%b fault=%d reads=%d",dut.found_mask,fault,debug_reads);if(dut.found_mask==0)$fatal(1,"FAIL empty scan");end
 end
 integer j,n,w,h,x,y,red,green,blue,cycles;reg [31:0] expected;
 initial begin
  a_reader.sd_card_top_m0.spi_master_m0.missing_slot2=MISSING_TWO;
  repeat(20)@(negedge net_clk);rst_n=1;wait(available==(MISSING_TWO?59:63));@(negedge net_clk);
  $display("B cache complete at %t fault=%d failed=%b found=%b",$time,fault,dut.failed_mask,dut.found_mask);
  if(MISSING_TWO && dut.found_mask[2]!==0)$fatal(1,"FAIL: scan admitted invalid source");
  if(STALL && (!stall_recovered || fault==0))$fatal(1,"FAIL: source watchdog recovery not exercised");
  if((!STALL && fault!=0) || (STALL?dut.U3.writes<1536000:dut.U3.writes!=(MISSING_TWO?1536000:1843200)))$fatal(1,"FAIL: producer complete cache fault=%d writes=%d",fault,dut.U3.writes);
  for(j=0;j<6;j=j+1)if(!(MISSING_TWO && j==2))begin
   role=j;w=FULL_IMAGES?(j==4?427:640):(j==3?800:j==4?1280:640);h=FULL_IMAGES?(j==4?321:480):1;
   if(sizes[j*32+:32]!=={16'(h),16'(w)})$fatal(1,"FAIL: producer source dimensions");
   req=1;wait(ack);@(negedge net_clk);req=0;repeat(8)@(negedge net_clk);
   for(n=0;n<307200;n=n+1)begin
    while(empty)@(negedge net_clk);
    en=1;@(negedge net_clk);en=0;
    x=(n%640)*w/640;y=FULL_IMAGES?((479-n/640)*h/480):0;red=(x^j)&255;green=y&255;blue=(x+y+j)&255;
    if(w>640 && x!=0)begin red=(red+(((x-1)^j)&255)+1)/2;blue=(blue+((x-1+y+j)&255)+1)/2;end
    expected={8'(red),8'(green),8'(blue),8'd0};
    if(data!==expected)$fatal(1,"FAIL: producer real FIFO/read pixel role=%d index=%d actual=%h expected=%h",j,n,data,expected);
    @(negedge net_clk);
   end
   $display("B role %0d read complete at %t",j,$time);repeat(10)@(negedge net_clk);
  end
  $display("PASS: A physical TF SPI -> protocol-v7 sector transfer -> B production FAT32 fragment reader, BMP scaling/prefilter, actual asynchronous FIFO IP and frame read/write arbiter: six 307200-pixel caches, only complete valid RAM writes and independently checked reads; invalid role 2 excluded by scan; normal and deliberately invalid role-2 sources, source dimensions, width/height mailbox and compact addresses");$finish;
 end
 initial begin #100000000;$display("DEBUG 100ms cache=%b found=%b source=%d Breq=%d Astate=%d sd=%d fault=%d",dut.cache_mask,dut.found_mask,dut.state,dut.remote_tf.u_bridge.state,a_reader.state,a_reader.sd_state,fault);end
 initial begin #2000000000;$fatal(1,"FAIL: producer timeout state=%d cache=%b parser=%d fault=%d role=%d pixel=%d fifo=%d readstate=%d readcnt=%d",dut.state,available,dut.bmp_read_m0.state,fault,j,n,dut.u_frames.wrusedw,dut.u_frames.frame_fifo_read_m0.state,dut.u_frames.frame_fifo_read_m0.read_cnt);end
endmodule
