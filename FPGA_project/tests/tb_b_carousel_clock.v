`timescale 1ns/1ps
module tb_b_carousel_clock;
 reg clk=0,rst=1,online=1,emergency=0;reg [1:0] switches=0;reg [4:0] feedback=5'b01110;
 wire [7:0] phase;integer n,begin_fade,cycles=0;
 always #20 clk=~clk;always @(posedge clk)cycles=cycles+1;
 distributed_carousel_clock #(.CLK_FREQ_HZ(1000)) dut(.clk(clk),.rst(rst),.switches(switches),.period_step(1'b0),
  .online(online),.feedback(feedback),.actual_emergency(emergency),.phase(phase));
 task clocks;input integer n;begin repeat(n)@(negedge clk);end endtask
 task check;input ok;input [1023:0] message;begin if(ok!==1'b1)$fatal(1,"FAIL: %0s",message);end endtask
 task full_fade;begin wait(phase[1]);@(negedge clk);clocks(300);check(!phase[2],"missing fade ACK still committed");feedback[4]=1;begin_fade=cycles;wait(phase[2]);@(negedge clk);
  check(cycles-begin_fade==160,"fade is not exactly 160 milliseconds");end endtask
 initial begin
 clocks(6);rst=0;clocks(2);check(phase[5] && phase[4:3]==0,"default active period");
 repeat(5)begin switches=1;clocks(3);switches=0;clocks(3);end
 clocks(24);check(phase[4:3]==0,"switch bounce changed period");
 switches=1;clocks(28);check(phase[4:3]==1 && dut.elapsed<8,"5s switch applied and fresh dwell");
 wait(phase[1]);@(negedge clk);begin_fade=cycles;
 switches=2;clocks(24);check(phase[4:3]==1,"period interrupted active fade");
 feedback[4]=1;begin_fade=cycles;wait(phase[2]);@(negedge clk);check(cycles-begin_fade==160,"5s full fade window");
 check(dut.elapsed==5000,"5s deadline");clocks(300);check(phase[2],"deadline was not held until committed epoch ACK");
 feedback[0]=1;feedback[3]=0;feedback[4]=0;clocks(2);check(phase[4:3]==2 && !phase[2] && !phase[1],"new frame epoch not acknowledged");
 wait(dut.elapsed==9839);clocks(1000);check(!phase[1]&&!phase[2]&&dut.elapsed==9839,"incomplete frame did not freeze before fade");
 feedback[3]=1;full_fade;check(dut.elapsed==10000,"10s deadline");
 feedback[2]=0;clocks(2);check(!phase[5]&&!phase[1]&&!phase[2],"pause ignored");
 feedback[2]=1;clocks(2);check(phase[5]&&dut.elapsed<5,"resume did not restart dwell");
 emergency=1;clocks(2);check(!phase[5],"emergency not excluded");emergency=0;clocks(2);check(phase[5]&&dut.elapsed<5,"emergency return stale deadline");
 online=0;clocks(2);check(!phase[5],"offline scheduler stayed active");online=1;clocks(2);check(phase[5]&&dut.elapsed<5,"reconnect did not restart");
 $display("PASS: B switch debounce, configurable 3/5/10s, epoch ACK, pause/resume, disconnect/reconnect, emergency exclusion, slow-prefetch hold, missing fade ACK and exact 160ms fade; period changes defer through active fade");$finish;
 end
 initial begin #2000000;$fatal(1,"B scheduler timeout");end
endmodule
