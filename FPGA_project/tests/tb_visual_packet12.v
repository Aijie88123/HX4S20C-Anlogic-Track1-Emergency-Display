`timescale 1ns/1ps
module tb_visual_packet12;
 reg clk=0;always #20 clk=~clk;
 reg rst=1,valid=0,ready=1;reg [223:0] packet=0;
 wire out_valid,band_valid,live;wire[223:0] out_packet;wire[19:0] data;wire[31:0] gaps;
 distributed_spectrum_worker #(.HIGH_ACCURACY(1)) dut(.clk(clk),.rst(rst),.online(1'b1),.packet_valid(valid),.packet(packet),
  .stream_ready(ready),.stream_valid(out_valid),.stream_data(out_packet),.gap_count(gaps));
 distributed_spectrum_client client(.clk(clk),.rst(rst),.online(1'b1),.packet_valid(out_valid&&ready),.packet(out_packet),
  .band_ready(1'b1),.band_valid(band_valid),.band_data(data),.live(live));
 reg[23:0] samples[0:34815];reg[15:0] expected[0:203];integer result=0,k,j;
 reg[15:0] sequence_id=0;reg[191:0] stalled;integer saw_stall=0;
 always @(negedge clk)if(!rst&&band_valid)begin
  if(data[19:16]!==result%12 || data[15:0]!=={expected[result][11:0],4'd0})
   $fatal(1,"Precise V12 order/value mismatch n%0d got%h expected%h",result,data,expected[result]);
  result=result+1;
 end
 always @(negedge clk)if(!rst&&out_valid&&!ready)begin
  if(saw_stall&&out_packet[223:32]!==stalled)$fatal(1,"Spectrum changed under backpressure");
  stalled=out_packet[223:32];saw_stall=1;
 end
 initial begin
  $readmemh("visual_dft_samples.hex",samples);$readmemh("visual_dft_expected.hex",expected);
  repeat(8)@(negedge clk);rst=0;
  for(k=0;k<6144;k=k+4)begin
   wait(dut.samples_left==0&&!dut.analyzer_busy);repeat(4)@(negedge clk);
   packet={96'd0,samples[k+3],samples[k+2],samples[k+1],samples[k],sequence_id,7'd0,k==0,8'd1};
   valid=1;@(negedge clk);valid=0;
   if(k==400)begin repeat(2)@(negedge clk);valid=1;@(negedge clk);valid=0;end
   sequence_id=sequence_id+1'b1;
  end
  wait(result==36);if(gaps!=0||!live||!saw_stall)$fatal(1,"Valid stream/backpressure coverage missing");
  // A missing input block must discard the partial DFT window.
  for(k=0;k<400;k=k+4)begin
   wait(dut.samples_left==0&&!dut.analyzer_busy);repeat(4)@(negedge clk);
   packet={96'd0,samples[k+3],samples[k+2],samples[k+1],samples[k],sequence_id,8'd0,8'd1};
   valid=1;@(negedge clk);valid=0;sequence_id=sequence_id+1'b1;
  end
  wait(dut.samples_left==0&&!dut.analyzer_busy);repeat(4)@(negedge clk);
  sequence_id=sequence_id+1'b1;
  packet={96'd0,96'd0,sequence_id,8'd0,8'd1};valid=1;@(negedge clk);valid=0;
  repeat(1000)@(negedge clk);
  if(gaps!=1||result!=36)$fatal(1,"Gap published partial powers");
  $display("PASS: three complete12-bin V12 packets and36 serialized independent golden powers; exact original PCM packing/client semantics, output held under backpressure, duplicate suppression and partial-window cancellation after a missing block");$finish;
 end
 initial begin #150000000;$fatal(1,"Packet test timeout result%0d",result);end
 initial begin wait(!rst);wait(out_valid);@(negedge clk);ready=0;repeat(20)@(negedge clk);ready=1;end
endmodule
