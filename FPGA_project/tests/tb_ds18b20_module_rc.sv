`timescale 1ns/1ps
module tb_ds18b20_module_rc;
 parameter integer CLK_HZ=1000000,C_PF=470;
 localparam integer R_OHM=10000;
 // Qualification envelope only: R*C rise to 80% of 3.3V, not a measured FPGA threshold.
 localparam integer RISE_NS=$rtoi($ceil(R_OHM*C_PF*0.001*1.6094379124341));
 reg clk=0;always #(500000000.0/CLK_HZ)clk=~clk;
 reg rst=1,enabled=1,corrupt=0;reg signed [15:0] input_temp=401;
 wire master_low,slave_low;wire combined_low=master_low||slave_low;
 wire pull_level;assign #(RISE_NS,0) pull_level=combined_low?1'b0:1'b1;
 tri dq;assign (weak1,weak0) dq=pull_level;assign dq=master_low?1'b0:1'bz;
 wire signed [15:0] raw;wire rv,sv,fault_pulse,busy;wire [2:0] fault;
 ds18b20_master #(.CLK_HZ(CLK_HZ)) dut(.clk(clk),.rst(rst),.dq_in(dq),.drive_low(master_low),
  .temperature_raw(raw),.reading_valid(rv),.sample_valid(sv),.fault_pulse(fault_pulse),.fault_code(fault),.busy(busy));
 ds18b20_rc_model device(.dq(dq),.drive_low(slave_low),.enabled(enabled),.stuck_low(1'b0),
  .corrupt_crc(corrupt),.busy_forever(1'b0),.bad_config(1'b0),.temperature(input_temp),
  .presence_delay_us(60),.presence_length_us(240),.read_zero_delay_ns(14900));
 integer samples=0,errors=0;
 always @(negedge clk)if(!rst)begin
  if(sv)begin samples=samples+1;$display("sample raw%0d t%t",$signed(raw),$time);end
  if(fault_pulse)begin errors=errors+1;$display("fault%0d t%t device mode%0d config%h",fault,$time,device.mode,device.config_byte);end
  if(dq===1'bx)$fatal(1,"contended DQ");
 end
 task sample(input integer expected);integer before_count;begin
  before_count=samples;wait(samples>before_count);@(negedge clk);#1;
  if(!rv||fault!=0||$signed(raw)!=expected)$fatal(1,"R10k C%0d clock%0d expected%0d raw%0d fault%0d",C_PF,CLK_HZ,expected,$signed(raw),fault);
 end endtask
 task error_code(input integer expected);integer before_count;begin
  before_count=errors;wait(errors>before_count);@(negedge clk);#1;
  if(rv||fault!=expected)$fatal(1,"fault expected%0d actual%0d",expected,fault);
 end endtask
 initial begin
  repeat(20*(CLK_HZ/1000000)+30)@(negedge clk);rst=0;
  sample(401);input_temp=-162;sample(-162);
  corrupt=1;error_code(3);corrupt=0;enabled=0;error_code(1);
  enabled=1;input_temp=720;sample(720);
  $display("PASS: onboardR=10000ohm C=%0dpF rise80=%0dns clk=%0d: full760ms conversion, raw401/-162/720, CRC reject, unplug and recovery; late14.9us data/max60us presence delay. samples=%0d errors=%0d",C_PF,RISE_NS,CLK_HZ,samples,errors);$finish;
 end
 initial begin #(64'd7000000000);$fatal(1,"RC test watchdog C%0d clk%0d samples%0d errors%0d",C_PF,CLK_HZ,samples,errors);end
endmodule
