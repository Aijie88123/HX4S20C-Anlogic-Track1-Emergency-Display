`timescale 1ns/1ps
module tb_uart_rom;
 reg clk=0;always #20 clk=~clk;reg [9:0] address=0;wire [7:0] q;
 reg [7:0] expected[0:1023];integer i;
 maintenance_text_rom dut(.clk(clk),.address(address),.q(q));
 initial begin
  $readmemh("../text_expected.hex",expected);repeat(12)@(negedge clk);
  for(i=0;i<1024;i=i+1)begin address=i;@(posedge clk);#2;if(q!==expected[i])$fatal(1,"native textROM address=%0d got=%h expected=%h",i,q,expected[i]);@(negedge clk);end
  $display("PASS: actual EG_PHY_BRAM INIT parameters,1024text bytes exact with synchronous read.");$finish;
 end
endmodule
