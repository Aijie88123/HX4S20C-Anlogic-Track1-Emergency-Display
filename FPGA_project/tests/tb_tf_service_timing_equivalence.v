`timescale 1ns/1ps
// Small deterministic SD surrogate for cycle-equivalence only. Separate
// physical-SPI and complete-chain regressions exercise the real SPI RTL.
module sd_card_top #(parameter CLK_FREQ_HZ=100000000,SPI_HIGH_SPEED_DIV=2)(
 input clk,rst,input sd_sec_read,input [31:0] sd_sec_read_addr,
 output reg sd_init_done,output reg [7:0] sd_sec_read_data,
 output reg sd_sec_read_data_valid,sd_sec_read_end,
 input sd_sec_write,input [31:0] sd_sec_write_addr,input [7:0] sd_sec_write_data,
 output sd_sec_write_data_req,sd_sec_write_end,
 output SD_nCS,SD_DCLK,SD_MOSI,input SD_MISO);
 reg [3:0] init_count;reg busy,phase;reg [9:0] index;reg [31:0] address;
 assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
 assign SD_nCS=!busy;assign SD_DCLK=busy&&phase;assign SD_MOSI=address[0];
 always @(posedge clk or posedge rst)begin
  if(rst)begin init_count<=0;sd_init_done<=0;busy<=0;phase<=0;index<=0;address<=0;
   sd_sec_read_data<=0;sd_sec_read_data_valid<=0;sd_sec_read_end<=0;end
  else begin
   sd_sec_read_data_valid<=0;sd_sec_read_end<=0;
   if(!sd_init_done)begin init_count<=init_count+1'b1;if(init_count==7)sd_init_done<=1;end
   if(sd_sec_read&&sd_init_done)begin busy<=1;phase<=0;index<=0;address<=sd_sec_read_addr;end
   else if(busy)begin
    phase<=!phase;
    if(phase&&!address[0])begin
     sd_sec_read_data<=index[7:0]^address[7:0];sd_sec_read_data_valid<=1;
     if(index==511)begin busy<=0;sd_sec_read_end<=1;end else index<=index+1'b1;
    end
   end
  end
 end
endmodule

module tb_tf_service_timing_equivalence;
 parameter TIMEOUT=4096;
 reg sdclk=0,netclk=0,rst=1,online=1;
 always #5 sdclk=~sdclk;always #17 netclk=~netclk;
 reg host_valid=0;reg [223:0] host_packet=0;
 reg packet_valid=0;reg [223:0] packet=0;
 reg ack_pending=0;reg [223:0] ack_packet=0;
 integer net_cycles=0,checks=0,body_packets=0,status_packets=0;
 wire ready=net_cycles%4!=2;
 wire dv,rv,dc,dd,dm,rc,rd,rm;wire [223:0] dp,rp;
 a_tf_sector_service_timed #(.READ_TIMEOUT_CYCLES(TIMEOUT),.RETRY_CYCLES(40)) dut(
  .sd_clk(sdclk),.net_clk(netclk),.rst(rst),.online(online),.packet_valid(packet_valid),.packet(packet),
  .stream_valid(dv),.stream_data(dp),.stream_ready(ready),.sd_miso(1'b1),.sd_ncs(dc),.sd_dclk(dd),.sd_mosi(dm));
 a_tf_sector_service_reference #(.READ_TIMEOUT_CYCLES(TIMEOUT),.RETRY_CYCLES(40)) reference(
  .sd_clk(sdclk),.net_clk(netclk),.rst(rst),.online(online),.packet_valid(packet_valid),.packet(packet),
  .stream_valid(rv),.stream_data(rp),.stream_ready(ready),.sd_miso(1'b1),.sd_ncs(rc),.sd_dclk(rd),.sd_mosi(rm));
 always @(posedge sdclk)begin
  #1;
  if(!rst&&online)begin
   if({dut.sd_state,dut.sd_req,dut.result_valid,dut.result_ok,dut.count,dut.recovery}
      !=={reference.sd_state,reference.sd_req,reference.result_valid,reference.result_ok,reference.count,reference.recovery})
    $fatal(1,"Physical-service state/cycle changed timeout=%0d",TIMEOUT);
   if(dut.watchdog!==reference.watchdog)$fatal(1,"Watchdog count changed");
   if(dut.recovery_active!==(reference.recovery!=0))$fatal(1,"Recovery interval changed");
   if({dc,dd,dm}!=={rc,rd,rm})$fatal(1,"SD pin waveform changed");
   checks=checks+1;
  end
 end
 always @(posedge netclk)begin
  if(!rst&&online)begin
   if(dv!==rv || (dv&&dp!==rp))$fatal(1,"Network packet/valid changed");
   if(rv&&ready)begin
    if(rp[31:24]<32)begin
     body_packets=body_packets+1;ack_pending=1;ack_packet=0;
     ack_packet[7:0]=11;ack_packet[23:8]=rp[23:8];ack_packet[31:24]=rp[31:24];
    end else status_packets=status_packets+1;
   end
  end
 end
 always @(negedge netclk)begin
  packet_valid=0;net_cycles=net_cycles+1;
  if(rst||!online)begin ack_pending=0;packet=0;end
  else if(host_valid)begin packet=host_packet;packet_valid=1;end
  else if(ack_pending)begin packet=ack_packet;packet_valid=1;ack_pending=0;end
 end
 task request(input [15:0] id,input [31:0] lba);begin
  wait(dut.sd_state==0&&dut.state==0&&dut.sd_ready&&!dut.recovery_active);
  @(posedge netclk);#2;host_packet=0;host_packet[7:0]=9;host_packet[23:8]=id;
  host_packet[31:24]=1;host_packet[63:32]=lba;host_valid=1;
  @(posedge netclk);#2;host_valid=0;
  wait(dut.sd_state!=0);
  wait(dut.sd_state==0&&dut.state==0&&!dut.recovery_active);
 end endtask
 initial begin
  repeat(8)@(negedge sdclk);rst=0;
  request(16'h1001,32'd2);request(16'h1002,32'd3);
  if(TIMEOUT>=2048 && body_packets!=32)$fatal(1,"Successful 512-byte sector not covered");
  if(status_packets==0)$fatal(1,"Read timeout not covered");
  @(negedge sdclk);online=0;repeat(8)@(negedge netclk);online=1;
  request(16'h1003,32'd3);
  $display("PASS: A physical-service timing equivalent to accepted original, timeout=%0d cycles, %0d cycle checks, body=%0d status=%0d; exact watchdog/recovery/state/pins/packets and offline restart",TIMEOUT,checks,body_packets,status_packets);
  $finish;
 end
 initial begin #10000000;$fatal(1,"Equivalence timeout");end
endmodule
