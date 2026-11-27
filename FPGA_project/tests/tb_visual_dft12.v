`timescale 1ns/1ps
module tb_visual_dft12;
 reg clk=0;always #20 clk=~clk;
 reg rst=1,valid=0;reg signed [23:0] sample=0;
 wire busy,bv;wire [4:0] bi;wire [15:0] mag;
 audio_dft12 dut(.clk(clk),.rst(rst),.I_audio(sample),.I_audio_valid(valid),.busy(busy),.O_band_valid(bv),.O_band(bi),.O_mag(mag));
 reg [23:0] vectors[0:34815];reg [15:0] expected[0:203];
 integer sent=0,results=0,k;
 always @(negedge clk)if(bv)begin
  if(bi!==results%12 || mag!==expected[results])$fatal(1,"DFT mismatch %0d bin%0d got%0d expected%0d",results,bi,mag,expected[results]);
  results=results+1;
 end
 initial begin
  $readmemh("visual_dft_samples.hex",vectors);$readmemh("visual_dft_expected.hex",expected);
  repeat(8)@(negedge clk);rst=0;
  for(k=0;k<34816;k=k+1)begin
   while(busy)@(negedge clk);
   sample=vectors[k];valid=1;@(negedge clk);valid=0;repeat(3)@(negedge clk);sent=sent+1;
  end
  wait(results==204);repeat(5)@(negedge clk);
  $display("PASS: full-rate twelve-bin DFT,34816 independently generated samples and204 exact powers; eight notes/four alarm probes plus silence/DC/4262Hz anti-alias/multitone/original triangle, no dropped input");$finish;
 end
 initial begin #600000000;$fatal(1,"DFT test timeout %0d %0d",sent,results);end
endmodule
