`timescale 1ns/1ps
module tb_period_button;
 reg clk=0,rst=1,step=0,online=1,emergency=0;
 reg [1:0] switches=0;reg [4:0] feedback=5'b01110;
 wire [7:0] phase;integer ticks=0,fade_begin;
 always #20 clk=~clk;always @(posedge clk)ticks=ticks+1;
 distributed_carousel_clock #(.CLK_FREQ_HZ(1000)) dut(.clk(clk),.rst(rst),
  .switches(switches),.period_step(step),.online(online),.feedback(feedback),
  .actual_emergency(emergency),.phase(phase));
 task clocks(input integer count);repeat(count)@(negedge clk);endtask
 task check(input bit ok,input string message);if(!ok)$fatal(1,"%s",message);endtask
 task press;begin step=1;clocks(1);step=0;clocks(2);end endtask
 task fresh_epoch;begin feedback[0]=!feedback[0];feedback[4]=0;clocks(2);end endtask
 initial begin
  clocks(6);rst=0;clocks(30);
  check(phase[4:3]==0 && phase[5],"default 3s");
  press;check(phase[4:3]==1,"first release must choose 5s");
  clocks(100);check(phase[4:3]==1,"unchanged switch overwrote button");
  press;check(phase[4:3]==2,"second release must choose 10s");
  press;check(phase[4:3]==0,"third release must return 3s");
  wait(phase[1]);@(negedge clk);fade_begin=ticks;
  press;press;check(phase[4:3]==0,"button interrupted current fade");
  clocks(200);check(!phase[2],"missing fade ACK committed picture");
  feedback[4]=1;fade_begin=ticks;wait(phase[2]);@(negedge clk);
  check(ticks-fade_begin==160,"button shortened 160ms fade");
  check(phase[4:3]==0,"due frame changed its period before epoch ACK");
  fresh_epoch;check(phase[4:3]==2 && dut.elapsed<5,"latest pending button not applied at next frame");
  feedback[2]=0;clocks(2);press;check(!phase[5] && phase[4:3]==0,"paused selection not retained");
  clocks(200);feedback[2]=1;clocks(2);check(phase[5] && dut.elapsed<5,"resume must start fresh dwell");
  online=0;clocks(2);press;check(!phase[5] && phase[4:3]==1,"offline selection not retained");
  online=1;clocks(2);check(phase[5] && dut.elapsed<5,"reconnect must start selected 5s dwell");
  repeat(5)begin switches=2;clocks(3);switches=0;clocks(3);end
  clocks(24);check(phase[4:3]==1,"switch bounce reset manual selection");
  switches=2;clocks(28);check(phase[4:3]==2,"new debounced switch must choose 10s");
  press;clocks(30);check(phase[4:3]==0,"button cannot override stationary switch");
  switches=3;clocks(28);check(phase[4:3]==0,"switch 11 default mapping");
  press;clocks(30);check(phase[4:3]==1,"all-high switches overwrote button");
  emergency=1;clocks(2);check(!phase[5],"emergency must stop normal scheduler");
  emergency=0;clocks(2);check(phase[5] && phase[4:3]==1 && dut.elapsed<5,"emergency return lost chosen period");
  rst=1;clocks(3);switches=0;rst=0;clocks(30);check(phase[4:3]==0,"reset default");
  $display("PASS: button 3/5/10s wrap; stationary/bouncing/new switches; pending changes through complete 160ms fade and epoch ACK; pause, offline, reconnect, emergency return, reset");$finish;
 end
 initial begin #3000000;$fatal(1,"period button scheduler timeout");end
endmodule
