`timescale 1ns/1ps
module tb_sensor_owner_equivalence;
 reg clk=0,rst=1,toggle=0,step=0,valid=0;reg [10:0] command=0;always #5 clk=~clk;
 wire a,b;wire [1:0] ae,be;
 dual_board_emergency_control dut(clk,rst,toggle,step,valid,command,a,ae);
 sensor_owner_reference reference_policy(clk,rst,toggle,step,valid,command,b,be);
 integer checks=0,i,j;reg [31:0] rng=32'h9a0b3721;
 always @(posedge clk)begin #1;
  if({a,ae,dut.remote_owner}!=={b,be,reference_policy.remote_owner})
   $fatal(1,"owner encoding differs cycle%0d input%h states%h/%h",checks,{rst,toggle,step,valid,command},{a,ae,dut.remote_owner},{b,be,reference_policy.remote_owner});
  checks=checks+1;
 end
 initial begin
  repeat(3)@(negedge clk);rst=0;
  for(j=0;j<4;j=j+1)for(i=0;i<16384;i=i+1)begin
   @(negedge clk);command=i[10:0];valid=i[11];toggle=i[12];step=i[13];
   rst=(i==0);
  end
  for(i=0;i<65536;i=i+1)begin
   @(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
   {toggle,step,valid,command}=rng[13:0];rst=(i%997==0);
  end
  @(negedge clk);$display("PASS: %0d cycle-exact comparisons of actual old guarded RTL versus local-owner encoding; all16384 input vectors repeated4 times,65536 mixed sequential vectors, reset and ownership alias.",checks);$finish;
 end
 initial begin #3000000;$fatal(1,"timeout");end
endmodule
