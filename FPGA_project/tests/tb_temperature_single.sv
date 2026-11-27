`timescale 1ns/1ps
module tb_temperature_single;
 parameter integer CLK_HZ=25000000;
 reg clk=0;always #(500000000.0/CLK_HZ)clk=~clk;
 reg rst=1,rv=0,sv=0,manual=0;reg signed [15:0] raw=0;
 wire fault,warn,allowed,alarm,rise,cleared;integer checks=0,rises=0;
 temperature_alarm #(.CLK_HZ(CLK_HZ),.STALE_MS(5)) dut(.clk(clk),.rst(rst),.reading_valid(rv),.sample_valid(sv),.temperature_raw(raw),.manual_clear(manual),.sensor_fault(fault),.warning_active(warn),.clear_allowed(allowed),.alarm_latched(alarm),.alarm_rise(rise),.alarm_cleared(cleared));
 task check(input bit ok,input string what);begin checks++;if(!ok)$fatal(1,"%s",what);end endtask
 task tick;begin @(negedge clk);#1;end endtask
 task sample(input integer v);begin @(negedge clk);raw=v;rv=1;sv=1;@(negedge clk);#1;sv=0;end endtask
 task cool;begin sample(800);sample(800);sample(800);end endtask
 task clear_now;begin manual=1;tick();manual=0;tick();check(!alarm,"qualified manual clear");end endtask
 always @(negedge clk)if(!rst&&rise)begin rises++;$display("rise %0d at %t raw %0d",rises,$time,$signed(raw));end
 initial begin
  repeat(4)tick();rst=0;tick();check(fault&&!alarm,"boot has no qualified sample");
  raw=880;rv=0;sv=1;tick();sv=0;check(!alarm,"invalid hot data must not trigger");
  rv=1;repeat(4)tick();check(!alarm,"reading without fresh sample must not trigger");
  sample(880);check(alarm&&rise&&!allowed,"FIRST valid sample at exact55C must latch, including boot fault state");
  tick();check(!rise,"alarm rise is one clock");sample(2000);check(alarm&&!rise,"latched high samples do not retrigger");
  rv=0;tick();check(fault&&alarm&&!allowed,"fault retains lock and prohibits clear");manual=1;tick();manual=0;check(alarm,"fault cannot clear");
  sample(800);check(!allowed,"first cool sample insufficient");sample(800);check(!allowed,"second cool sample insufficient");
  sample(801);check(!allowed,"50.0625C breaks cool run");cool();check(allowed,"three valid exact50C samples permit manual clear");
  @(negedge clk);manual=1;raw=880;sv=1;tick();manual=0;sv=0;check(alarm&&!allowed&&!rise&&!cleared,"same-edge hot sample blocks old cool clear decision without clear/retrigger");
  cool();rv=0;tick();check(!allowed,"fault invalidates completed cool run");sample(800);sample(800);check(!allowed,"cool requalification after fault still requires three");sample(800);check(allowed,"cool recovery three");
  wait(dut.age==4 && dut.div==CLK_HZ/1000-1);@(negedge clk);manual=1;tick();manual=0;check(fault&&alarm&&!allowed,"same-edge stale threshold must block manual clear");
  cool();clear_now();
  sample(-162);check(!warn&&!alarm,"negative signed temperature");sample(719);check(!warn&&!alarm,"44.9375 below warning");sample(720);check(warn&&!alarm,"45C warning without alarm");sample(879);check(warn&&!alarm,"54.9375C below alarm");
  #6000000;check(fault&&!alarm,"stale data alone cannot trigger");sample(880);check(alarm&&rise,"FIRST valid sample after stale state must trigger");
  cool();clear_now();rv=0;tick();sample(880);check(alarm&&rise,"FIRST valid sample after disconnected state must rearm");
  tick();check(rises==3,$sformatf("exactly three alarm rise events, got %0d",rises));
  $display("PASS: CLK_HZ=%0d %0d checks; first-valid55C at boot/stale/recovery; signed boundaries; no invalid/stale/duplicate triggers; unchanged three-sample50C cool-down and fault/same-edge/manual-clear protection",CLK_HZ,checks);$finish;
 end
 initial begin #30000000;$fatal(1,"policy watchdog");end
endmodule
