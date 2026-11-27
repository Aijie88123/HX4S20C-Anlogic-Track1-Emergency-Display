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
module tb_physical_six_storage;
 reg aclk=0;always #5 aclk=~aclk;
 reg clk=0,net_clk=0,rst_n=0,req=0,en=0;reg [2:0] role=2;reg [1:0] readstate=0;
 always #10 clk=~clk;always #20 net_clk=~net_clk;
 wire ack,empty;wire [31:0] data;wire [5:0] available;wire [191:0] sizes;wire [3:0] fault;
 wire av,bv;wire [223:0] ap,bp;reg pa=0,pb=0;reg [223:0] ppa=0,ppb=0;
 reg [223:0] ahold,bhold;integer aflight=0,bflight=0,agap=0,bgap=0;
 wire ar=aflight==0&&agap==0,br=bflight==0&&bgap==0;
 wire ncs,sck,mosi,miso;
 a_tf_sector_service a_reader(.sd_clk(aclk),.net_clk(net_clk),.rst(!rst_n),.online(1'b1),
  .packet_valid(pa),.packet(ppa),.stream_valid(av),.stream_data(ap),.stream_ready(ar),.sd_miso(miso),.sd_ncs(ncs),.sd_dclk(sck),.sd_mosi(mosi));
 card_spi_physical_six card(.rst(!rst_n),.ncs(ncs),.sck(sck),.mosi(mosi),.miso(miso));
 always @(posedge net_clk)begin
  pa<=0;pb<=0;
  if(agap!=0)agap<=agap-1;if(bgap!=0)bgap<=bgap-1;
  if(av&&ar)begin ahold<=ap;aflight<=144;agap<=169;end
  if(bv&&br)begin bhold<=bp;bflight<=144;bgap<=169;end
  if(aflight!=0)begin aflight<=aflight-1;if(aflight==1)begin pb<=1;ppb<=ahold;end end
  if(bflight!=0)begin bflight<=bflight-1;if(bflight==1)begin pa<=1;ppa<=bhold;end end
 end
 b_media_storage #(.CLK_FREQ_HZ(50000000),.REMOTE_TF(1),.IMAGE_ROLES(6),.NUMBERED_SIX(1)) dut(.clk(clk),.rst_n(rst_n),.net_clk(net_clk),.net_rst(!rst_n),
  .sd_miso(1'b1),.sd_ncs(),.sd_dclk(),.sd_mosi(),
  .online(1'b1),.packet_valid(pb),.packet(ppb),.tf_stream_valid(bv),.tf_stream_data(bp),.tf_stream_ready(br),.read_req(req),.read_en(en),.read_role(role),
  .read_ack(ack),.read_empty(empty),.read_data(data),.available(available),.source_sizes(sizes),.source_fault(fault),.source_fault_recurring());
 integer debug_reads=0,debug_bytes=0;reg [7:0] debug_expected;
 always @(posedge aclk)if(a_reader.sd_req)debug_reads=debug_reads+1;
 always @(negedge dut.sd_clk)begin
  if(dut.byte_valid)begin
   debug_expected=card.card_byte(a_reader.sd_address,debug_bytes);
   if(dut.byte_data!==debug_expected)$fatal(1,"FAIL real SPI/B parser byte=%d LBA=%d actual=%h expected=%h",debug_bytes,a_reader.sd_address,dut.byte_data,debug_expected);
   debug_bytes=debug_bytes+1;
  end
  if(dut.sec_end)begin
   if(debug_bytes!=512)$fatal(1,"FAIL incomplete physical source sector bytes=%d",debug_bytes);
   debug_bytes=0;
  end
 end
 integer j,n,w,h,x,y,red,green,blue;reg [31:0] expected;
 initial begin
  repeat(20)@(negedge net_clk);rst_n=1;wait(available==63);@(negedge net_clk);
  if(fault!=0||dut.U3.writes!=1843200)$fatal(1,"FAIL physical six cache fault=%d writes=%d",fault,dut.U3.writes);
  for(j=0;j<6;j=j+1)begin
   w=j==3?800:j==4?1280:640;h=1;
   if(sizes[j*32+:32]!=={16'(h),16'(w)})$fatal(1,"FAIL physical six dimensions role=%d",j);
   for(n=0;n<307200;n=n+1)begin
    x=(n%640)*w/640;y=0;red=(x^j)&255;green=0;blue=(x+j)&255;
    if(w>640 && x!=0)begin red=(red+(((x-1)^j)&255)+1)/2;blue=(blue+((x-1+j)&255)+1)/2;end
    expected={8'(red),8'(green),8'(blue),8'd0};
    if(dut.U3.ram[j*307200+n]!==expected)$fatal(1,"FAIL real SPI six SDRAM pixel role=%d index=%d got=%h expected=%h",j,n,dut.U3.ram[j*307200+n],expected);
   end
   $display("TRACE: real SPI six source %0d %0dx1 independently checked 307200 complete cached pixels",j,w);
  end
  if(debug_reads<30||card.delayed_responses<8*debug_reads)$fatal(1,"FAIL physical six command coverage reads=%d polls=%d",debug_reads,card.delayed_responses);
  $display("PASS: production spi_master at real A SPI pins with 22ns MISO/100ms cold wait/delayed R1 and token -> A sector service -> sector payload packets with Ethernet occupancy -> B production FAT32/BMP parser/scaler/real FIFO/SDRAM writer: six source images (640/800/1280 widths), all 1843200 output cache pixels independently verified, six source-size records, no partial cache or faults; sectors=%0d",debug_reads);
  $finish;
 end
 initial begin #2000000000;$fatal(1,"FAIL physical six timeout cache=%b parser=%d fault=%d reads=%d",available,dut.bmp_read_m0.state,fault,debug_reads);end
endmodule
