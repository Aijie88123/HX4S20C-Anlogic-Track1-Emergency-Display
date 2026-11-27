`timescale 1ns/1ps

// v3 stream byte layout (little endian): kind, restart flag, sequence16,
// then four exact signed24 PCM samples (A->B), or twelve power16 (B->A).
// The rest of the Ethernet padding is zero. Audio generation never waits
// for Ethernet. A four-sample packet uses ~8.1Mbps including preamble/IFG.
module distributed_pcm_sender(
 input clk,rst,online,input sample_valid,input [23:0] sample,input sample_restart,
 input stream_ready,output stream_valid,output [223:0] stream_data);
 reg [95:0] words;
 reg [1:0] count;
 reg pending,restart_block;
 reg [15:0] packet_sequence;
 assign stream_valid=pending && online;
 assign stream_data={96'd0,words,packet_sequence,7'd0,restart_block,8'd1};
 always @(posedge clk or posedge rst)
  if(rst)begin words<=0;count<=0;pending<=0;packet_sequence<=0;restart_block<=1;end
  else if(!online)begin count<=0;pending<=0;restart_block<=1;end
  else begin
   if(pending && stream_ready)begin pending<=0;packet_sequence<=packet_sequence+1'b1;restart_block<=0;end
   if(sample_valid)begin
    // A mailbox drop or a stalled packet discards the partial block. The
    // next transmitted block explicitly resets B's analysis window.
    if(sample_restart || (pending && !stream_ready))begin
     words<={sample,72'd0};count<=1;pending<=0;restart_block<=1;
    end else begin
     words<={sample,words[95:24]};
     if(count==3)begin count<=0;pending<=1;end else count<=count+1'b1;
    end
   end
  end
endmodule

// B replays each contiguous packet with at least 64 clocks between samples.
// Goertzel's state and 48-clock result stage depend on sample order, not
// Ethernet arrival time. No samples are interpolated or re-quantized.
module distributed_spectrum_worker #(parameter HIGH_ACCURACY=0)(
 input clk,rst,online,input packet_valid,input [223:0] packet,
 input stream_ready,output stream_valid,output [223:0] stream_data,
 output reg [31:0] gap_count);
 reg [95:0] pcm;
 reg [2:0] samples_left;
 reg [6:0] spacing;
 reg [15:0] last_sequence,window_sequence;
 reg have_sequence,reset_analysis,first_window,pending,held_first;
 reg [191:0] magnitudes;
 wire [15:0] packet_sequence=packet[31:16];
 wire [15:0] distance=packet_sequence-last_sequence;
 wire duplicate=have_sequence && !packet[8] && distance==0;
 wire obsolete=have_sequence && !packet[8] && distance[15];
 wire incoming=packet_valid && packet[7:0]==1 && !duplicate && !obsolete;
 wire discontinuity=!have_sequence || packet[8] || distance!=1 || samples_left!=0;
 wire analyzer_busy;
 wire audio_valid=samples_left!=0 && spacing==0 && !reset_analysis && !incoming && !analyzer_busy;
 wire band_valid;wire [4:0] band;wire [15:0] magnitude;
 generate if(HIGH_ACCURACY)begin:full_rate
  audio_dft12 u_dft(.clk(clk),.rst(rst || !online || reset_analysis),.I_audio(pcm[23:0]),.I_audio_valid(audio_valid),
   .busy(analyzer_busy),.O_band_valid(band_valid),.O_band(band),.O_mag(magnitude));
 end else begin:legacy
  assign analyzer_busy=1'b0;
  audio_fft #(.P_BINS(12),.P_WIN(64)) u_audio_fft(
   .clk(clk),.rst(rst || !online || reset_analysis),.I_audio(pcm[23:0]),.I_audio_valid(audio_valid),
   .O_band_valid(band_valid),.O_band(band),.O_mag(magnitude));
 end endgenerate
 assign stream_valid=pending && online && !reset_analysis;
 assign stream_data={magnitudes,window_sequence,7'd0,held_first,8'd2};
 always @(posedge clk or posedge rst)
  if(rst)begin
   pcm<=0;samples_left<=0;spacing<=0;last_sequence<=0;window_sequence<=0;
   have_sequence<=0;reset_analysis<=1;first_window<=1;pending<=0;held_first<=1;
   magnitudes<=0;gap_count<=0;
  end else if(!online)begin
   samples_left<=0;have_sequence<=0;reset_analysis<=1;first_window<=1;pending<=0;spacing<=0;
  end else begin
   reset_analysis<=0;
   if(pending && stream_ready)pending<=0;
   if(spacing!=0)spacing<=spacing-1'b1;
   if(audio_valid)begin pcm<=pcm>>24;samples_left<=samples_left-1'b1;spacing<=63;end
   if(band_valid && !reset_analysis)begin
    if(HIGH_ACCURACY)magnitudes<={magnitude[11:0],4'd0,magnitudes[191:16]};
    else magnitudes[band*16 +:16]<=magnitude;
    if(band==11)begin
     pending<=1;window_sequence<=window_sequence+1'b1;
     held_first<=first_window;first_window<=0;
    end
   end
   if(incoming)begin
    pcm<=packet[127:32];samples_left<=4;spacing<=discontinuity?7'd4:7'd0;
    last_sequence<=packet_sequence;have_sequence<=1;
    if(discontinuity)begin
     reset_analysis<=1;first_window<=1;pending<=0;
     if(have_sequence)gap_count<=gap_count+1'b1;
    end
   end
  end
endmodule

// A returns only complete CRC-checked power sets to the video domain. The
// narrow mailbox serializes bands without copying a 192-bit window twice.
module distributed_spectrum_client #(parameter LIVE_CYCLES=5000000)(
 input clk,rst,online,input packet_valid,input [223:0] packet,
 input band_ready,output band_valid,output [19:0] band_data,output live);
 reg [191:0] powers;
 reg [3:0] index;
 reg emitting,have_sequence;
 reg [15:0] last_sequence;
 reg [22:0] age;
 wire [15:0] distance=packet[31:16]-last_sequence;
 wire fresh=packet_valid && packet[7:0]==2 &&
  (!have_sequence || packet[8] || (distance!=0 && !distance[15]));
 assign band_valid=emitting && online;
 assign band_data={index,powers[15:0]};
 assign live=online && have_sequence && age<LIVE_CYCLES;
 always @(posedge clk or posedge rst)
  if(rst)begin powers<=0;index<=0;emitting<=0;have_sequence<=0;last_sequence<=0;age<=LIVE_CYCLES;end
  else if(!online)begin emitting<=0;have_sequence<=0;age<=LIVE_CYCLES;end
  else begin
   if(age<LIVE_CYCLES)age<=age+1'b1;
   if(emitting && band_ready)begin
    powers<=powers>>16;
    if(index==11)begin emitting<=0;index<=0;end else index<=index+1'b1;
   end
   if(fresh)begin
    powers<=packet[223:32];index<=0;emitting<=1;
    have_sequence<=1;last_sequence<=packet[31:16];age<=0;
   end
  end
endmodule
