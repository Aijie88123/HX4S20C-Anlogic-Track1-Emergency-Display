`timescale 1ns/1ps
module tb_spectrum_faults;
 reg clk=0;always #20 clk=~clk;
 reg rst=1,online=1,valid=0,ready=1;
 reg [223:0] packet=0;
 wire out_valid;wire [223:0] out_packet;wire [31:0] gaps;
 distributed_spectrum_worker worker(.clk(clk),.rst(rst),.online(online),.packet_valid(valid),.packet(packet),
  .stream_ready(ready),.stream_valid(out_valid),.stream_data(out_packet),.gap_count(gaps));
 reg ref_reset=1,ref_valid=0;reg [23:0] ref_sample=0;
 wire ref_band_valid;wire [4:0] ref_band;wire [15:0] ref_magnitude;
 audio_fft_reference #(.P_BINS(12),.P_WIN(64)) reference(.clk(clk),.rst(ref_reset),.I_audio(ref_sample),
  .I_audio_valid(ref_valid),.O_band_valid(ref_band_valid),.O_band(ref_band),.O_mag(ref_magnitude));
 reg [15:0] golden[0:11];integer complete=0,ref_complete=0;
 // Store worker results until the slower independent reference has retired.
 reg [191:0] remote_result;
 always @(posedge clk)begin
  if(out_valid && ready)begin remote_result=out_packet[223:32];complete=complete+1;end
  if(ref_band_valid)begin
   golden[ref_band]=ref_magnitude;
   if(ref_band==11)begin
    for(integer j=0;j<12;j=j+1)if(remote_result[j*16+:16]!==golden[j])
      $fatal(1,"Fault recovery spectrum differs at band %0d",j);
    ref_complete=ref_complete+1;
   end
  end
 end
 integer sample_number=0;
 task block(input [15:0] seq,input restart,input accepted);
  reg [95:0] words;integer j;integer value;
  begin
   words=0;
   for(j=0;j<4;j=j+1)begin
    value=$rtoi(2000000.0*$sin(6.283185307179586*329.63*(sample_number+j)/48000.0));
    words[j*24+:24]=value;
   end
   if(restart && accepted)begin ref_reset=1;repeat(2)@(negedge clk);ref_reset=0;end
   @(negedge clk);packet={96'd0,words,seq,7'd0,restart,8'd1};valid=1;
   @(negedge clk);valid=0;
   if(accepted)begin
    sample_number=sample_number+4;
    for(j=0;j<4;j=j+1)begin
     repeat(120)@(negedge clk);ref_sample=words[j*24+:24];ref_valid=1;
     @(negedge clk);ref_valid=0;
    end
   end
   repeat(200)@(negedge clk);
  end
 endtask
 // Exercise client filtering independently of the worker's return traffic.
 reg cv=0,conline=1;reg [223:0] cp=0;
 wire cbv,clive;wire [19:0] cbd;integer returned=0;
 distributed_spectrum_client #(.LIVE_CYCLES(2000)) client(.clk(clk),.rst(rst),.online(conline),
  .packet_valid(cv),.packet(cp),.band_ready(1'b1),.band_valid(cbv),.band_data(cbd),.live(clive));
 always @(posedge clk)if(cbv)begin
  if(cbd[15:0]!==16'h2345)$fatal(1,"Client emitted incorrect power");
  returned=returned+1;
 end
 task result_packet(input [15:0] seq,input restart);
  begin
   @(negedge clk);cp={{12{16'h2345}},seq,7'd0,restart,8'd2};cv=1;
   @(negedge clk);cv=0;repeat(20)@(negedge clk);
  end
 endtask
 integer i;reg [15:0] packet_sequence;
 initial begin
  #100;rst=0;ref_reset=0;packet_sequence=16'd65500;
  for(i=0;i<192;i=i+1)begin
   block(packet_sequence,i==0,1);
   if(i==20)begin block(packet_sequence,0,0);block(packet_sequence-1'b1,0,0);end
   packet_sequence=packet_sequence+1'b1;
  end
  repeat(200)@(negedge clk);
  if(complete!=1 || ref_complete!=1 || gaps!=0)$fatal(1,"Duplicate/obsolete/wrap filtering failed");
  for(i=0;i<10;i=i+1)begin block(packet_sequence,0,1);packet_sequence=packet_sequence+1'b1;end
  // Lose one block. The following gap resets both partial analysis windows.
  packet_sequence=packet_sequence+1'b1;ref_reset=1;repeat(2)@(negedge clk);ref_reset=0;
  for(i=0;i<192;i=i+1)begin block(packet_sequence,0,1);packet_sequence=packet_sequence+1'b1;end
  repeat(200)@(negedge clk);
  if(complete!=2 || ref_complete!=2 || gaps!=1)$fatal(1,"Missing PCM block did not restart one complete window");
  online=0;ref_reset=1;repeat(20)@(negedge clk);
  if(out_valid)$fatal(1,"Offline worker retained a spectrum result");
  online=1;ref_reset=0;packet_sequence=0;
  for(i=0;i<192;i=i+1)begin block(packet_sequence,i==0,1);packet_sequence=packet_sequence+1'b1;end
  repeat(200)@(negedge clk);
  if(complete!=3 || ref_complete!=3)$fatal(1,"Worker reconnect failed");
  result_packet(16'hffff,1);result_packet(0,0);
  if(returned!=24 || !clive)$fatal(1,"Client result wrap failed");
  result_packet(0,0);result_packet(16'hffff,0);
  if(returned!=24)$fatal(1,"Client repeated stale/duplicate result");
  result_packet(0,1);
  if(returned!=36)$fatal(1,"Client explicit restart failed");
  repeat(2100)@(negedge clk);if(clive)$fatal(1,"Stale spectrum marked live");
  conline=0;repeat(5)@(negedge clk);if(cbv || clive)$fatal(1,"Client offline failed");
  $display("PASS: exact spectrum after packet loss/reset; duplicate/obsolete rejection; packet_sequence wrap; reconnect; complete-result filtering; explicit restart; stale timeout");
  $finish;
 end
 initial begin #50000000;$fatal(1,"Spectrum fault test timeout");end
endmodule
