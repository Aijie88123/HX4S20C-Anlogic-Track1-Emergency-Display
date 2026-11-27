`timescale 1ns/1ps
module tb_slow_carousel_clock;
 reg clk=0,rst=1,online=1,emergency=0,step=0;reg [1:0] switches=0;
 reg [4:0] feedback=5'b11110;wire [7:0] phase;integer cycles=0,start,n;
 always #5 clk=~clk;always @(posedge clk)cycles=cycles+1;
 distributed_carousel_clock #(.CLK_FREQ_HZ(1000),.PERIOD0_MS(3000),.PERIOD1_MS(5000),.PERIOD2_MS(8000),.STARTUP_PERIOD_MS(3000)) dut(
  .clk(clk),.rst(rst),.switches(switches),.period_step(step),.online(online),.feedback(feedback),.actual_emergency(emergency),.phase(phase));
 task clocks(input integer count);begin repeat(count)@(negedge clk);end endtask
 task ack;begin @(negedge clk);feedback[0]=~feedback[0];wait(!phase[2]);@(negedge clk);end endtask
 task due_after(input integer ms);begin start=cycles;wait(phase[2]);@(negedge clk);if(cycles-start!=ms)$fatal(1,"period got=%0d expected=%0d",cycles-start,ms);end endtask
 task button;begin @(negedge clk);step=1;@(negedge clk);step=0;end endtask
 initial begin
  clocks(5);rst=0;wait(phase[5]);@(negedge clk);due_after(3000);
  ack();due_after(3000);ack();button();wait(phase[4:3]==1);@(negedge clk);due_after(5000);
  ack();button();wait(phase[4:3]==2);@(negedge clk);due_after(8000);
  ack();button();wait(phase[4:3]==0);@(negedge clk);feedback[4:3]=0;clocks(9000);
  if(phase[1]||phase[2])$fatal(1,"incomplete next image advanced");
  feedback[3]=1;wait(phase[1]);@(negedge clk);clocks(500);if(phase[2])$fatal(1,"fade ACK missing but committed");
  feedback[4]=1;due_after(160);clocks(500);if(!phase[2])$fatal(1,"due did not remain held for epoch ACK");
  ack();emergency=1;clocks(10);if(phase[5]||phase[1]||phase[2])$fatal(1,"emergency leaked normal carousel");
  emergency=0;wait(phase[5]);@(negedge clk);due_after(3000);ack();
  feedback[2]=0;clocks(10);if(phase[5])$fatal(1,"pause ignored");feedback[2]=1;wait(phase[5]);@(negedge clk);due_after(3000);ack();
  online=0;clocks(10);if(phase[5])$fatal(1,"offline ignored");online=1;wait(phase[5]);@(negedge clk);due_after(3000);
  ack();switches=1;wait(phase[4:3]==1);@(negedge clk);due_after(5000);
  ack();switches=2;wait(phase[4:3]==2);@(negedge clk);due_after(8000);
  ack();switches=3;wait(phase[4:3]==0);@(negedge clk);due_after(3000);
  ack();switches=0;clocks(30);if(phase[4:3]!=0)$fatal(1,"switch00 fallback");
  $display("PASS: exact first3000ms then3000/5000/8000ms; button wrap, incomplete-next hold, fade ACK, due epoch hold, emergency/pause/offline and resume without repeating startup dwell");$finish;
 end
 initial begin #2000000;$fatal(1,"fast clock timeout");end
endmodule
