`timescale 1ns/1ps
module tb_sensor_log;
 reg clk=0,rst=1,clear=0,start=0;always #20 clk=~clk;
 reg [6:0] valid=0;reg [447:0] data=0;reg [6:0] requested=64;reg [5:0] address=0;
 wire [6:0] count,snap_count;wire [15:0] lost;wire busy,ready;wire [63:0] q;
 maintenance_event_log #(.EVENTS(7)) dut(.clk(clk),.rst(rst),.clear(clear),.event_valid(valid),.event_data(data),.count(count),.lost(lost),
 .snapshot_start(start),.requested(requested),.snapshot_busy(busy),.snapshot_ready(ready),.snapshot_count(snap_count),.snapshot_address(address),.snapshot_data(q));
 task clocks(input integer n);repeat(n)@(negedge clk);endtask
 task snap;begin start=1;clocks(1);start=0;wait(ready);clocks(1);end endtask
 task read_check(input [5:0] a,input [63:0] expected);begin address=a;clocks(2);if(q!==expected)$fatal(1,"snapshot %d got%h expected%h",a,q,expected);end endtask
 integer i;
 initial begin clocks(3);rst=0;clocks(1);
 snap;if(count!=0||snap_count!=0)$fatal(1,"empty snapshot exposed RAM");
 valid=127;for(i=0;i<7;i++)data[i*64+:64]=64'h100+i;clocks(1);valid=0;clocks(9);
 if(count!=7||lost!=0)$fatal(1,"simultaneous categories lost");snap;
 for(i=0;i<7;i++)read_check(i,64'h100+i);
 // The 64-row snapshot copy pauses draining. Same-category overwrite must be counted.
 start=1;clocks(1);start=0;wait(busy);@(negedge clk);valid=64;data[384+:64]=64'h201;clocks(1);data[384+:64]=64'h202;clocks(1);valid=0;
 wait(ready);clocks(10);if(lost!=1||count!=8)$fatal(1,"pending overwrite accounting count%0d lost%0d",count,lost);
 for(i=0;i<7;i++)read_check(i,64'h100+i);snap;read_check(7,64'h202);
 clear=1;clocks(1);clear=0;clocks(2);if(count!=0||lost!=0)$fatal(1,"clear");snap;if(snap_count!=0)$fatal(1,"clear leaked records");
 // Reset during a snapshot discards indices without clearing or exposing physical RAM.
 valid=1;data[0+:64]=64'h300;clocks(1);valid=0;clocks(3);start=1;clocks(1);start=0;wait(busy);@(negedge clk);rst=1;clocks(2);rst=0;clocks(2);
 snap;if(count!=0||snap_count!=0||lost!=0)$fatal(1,"reset snapshot state");
 $display("PASS: seven simultaneous categories, empty/copy/read pipeline, pending overwrite+LOST, immutable snapshot,clear,reset during copy.");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
