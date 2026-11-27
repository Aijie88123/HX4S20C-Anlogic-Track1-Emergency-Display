`timescale 1ns/1ps
module tb_boot_supervisor;
 reg video_clk=0;always #7 video_clk=~video_clk;
 reg mem_clk=0;always #4 mem_clk=~mem_clk;
 reg refclk=0,rst_n=1;reg [2:0] locks=3'b111;wire hold_reset;
 always #10 refclk=~refclk;
 board_startup_reset #(.STABLE_CYCLES(8)) dut(.ref_clk(refclk),.rst_n(rst_n),.clock_locks(locks),.reset_hold(hold_reset));
 wire mem_reset;time hold_release_time=0;
 startup_release_sync #(.STAGES(16)) memory_release(.clk(mem_clk),.async_fault(!rst_n),.startup_hold(hold_reset),.rst(mem_reset));
 always @(negedge hold_reset)hold_release_time=$time;
 always @(negedge mem_reset)if($time>0 && ($time%8!=4 || $time-hold_release_time<120))$fatal(1,"Memory release was not sixteen local clocks");
 wire reference_reset;
 startup_release_sync reference_release(.clk(refclk),.async_fault(!rst_n),.startup_hold(hold_reset),.rst(reference_reset));
 always @(negedge reference_reset)if($time>0 && ($time%20!=10 || $time-hold_release_time<40))$fatal(1,"Reference diagnostics reset release is not local");
 wire domain_reset;
 startup_release_sync video_release(.clk(video_clk),.async_fault(!rst_n),.startup_hold(hold_reset),.rst(domain_reset));
 reg [7:0] domain_state;
 always @(posedge video_clk or posedge domain_reset)if(domain_reset)domain_state<=0;else domain_state<=domain_state+1'b1;
 integer i;
 initial begin
  // No low reset input and all clocks already locked when configured.
  #1;if(hold_reset!==1)$fatal(1,"No deterministic configuration reset");
  repeat(5)@(negedge refclk);if(domain_state!==0 || !hold_reset)$fatal(1,"Released during configuration hold");
  locks=3'b101;repeat(5)@(negedge refclk);
  locks=3'b111;
  for(i=0;i<9;i=i+1)begin @(negedge refclk);if(!hold_reset)$fatal(1,"Lock disturbance skipped stable interval");end
  wait(!domain_reset);if($time%14!=7)$fatal(1,"Startup reset released outside local video clock edge");repeat(3)@(negedge refclk);
  if(reference_reset || domain_state==0 || ^domain_state===1'bx)$fatal(1,"Domain state was not initialized and released");
  locks=3'b110;repeat(20)@(negedge refclk);
  if(hold_reset)$fatal(1,"Later Ethernet relock discarded complete caches");
  locks=7;rst_n=0;#1;if(!domain_reset || !hold_reset)$fatal(1,"User reset did not assert asynchronously");
  repeat(3)@(negedge refclk);rst_n=1;
  for(i=0;i<9;i=i+1)begin @(negedge refclk);if(!hold_reset)$fatal(1,"User reset did not repeat stable startup");end
  wait(!hold_reset);repeat(2)@(negedge refclk);
  $display("PASS: configuration with reset key never asserted and PLLs already locked, interrupted lock settling, full deterministic reset with local reference/video-edge and sixteen memory-clock release, user reset repeat, Ethernet relock cache retention");$finish;
 end
 initial begin #10000;$fatal(1,"Boot reset timeout");end
endmodule
