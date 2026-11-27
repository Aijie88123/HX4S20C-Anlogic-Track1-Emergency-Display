`timescale 1ns/1ps
module tb_resource_dft_exact #(parameter LAYOUT=0);
 reg clk=0,rst=1,valid=0;reg signed [23:0] pcm=0;always #5 clk=~clk;
 wire nb,pb,nv,pv;wire [4:0] ni,pi;wire [15:0] nm,pm;
 audio_dft12 n(.clk(clk),.rst(rst),.I_audio(pcm),.I_audio_valid(valid),.busy(nb),.O_band_valid(nv),.O_band(ni),.O_mag(nm));
 ref_resource_audio_dft12 p(.clk(clk),.rst(rst),.I_audio(pcm),.I_audio_valid(valid),.busy(pb),.O_band_valid(pv),.O_band(pi),.O_mag(pm));
 integer cycle=0,results=0,sample_number=0,i,target,repeat_reset;reg commit;reg [3:0] committed_bin;reg [111:0] reconstructed;
 always @(posedge clk)begin
  commit=p.state==11;committed_bin=p.bin;cycle=cycle+1;#1;
  if(nb!==pb || nv!==pv || ni!==pi || nm!==pm || n.phase!==p.phase)$fatal(1,"DFT interface differs cycle=%0d state=%0d/%0d bin=%0d/%0d valid=%b/%b mag=%h/%h",cycle,n.state,p.state,n.bin,p.bin,nv,pv,nm,pm);
  if(nv)results=results+1;
 end
 generate if(LAYOUT==0)begin
 always @(posedge clk)begin #2;if(commit && !rst)begin
   reconstructed={n.state_pq[committed_bin*4+1],n.state_pq[committed_bin*4],n.state_iq[committed_bin*4+2][15:8],n.state_iq[committed_bin*4+1],n.state_iq[committed_bin*4],n.state_iq[committed_bin*4+2][7:0],n.state_pq[committed_bin*4+3],n.state_pq[committed_bin*4+2]};
   if(reconstructed!==p.states[committed_bin])$fatal(1,"packed state differs at original commit cycle=%0d bin=%0d",cycle,committed_bin);
  end end
 end else if(LAYOUT==1)begin
 always @(posedge clk)begin #2;if(commit && !rst)begin
  reconstructed={n.phase+p.increment(committed_bin),n.states[committed_bin]};
  if(reconstructed!==p.states[committed_bin])$fatal(1,"computed phase/sums differ at original commit cycle=%0d bin=%0d",cycle,committed_bin);
 end end
 end else begin
 always @(posedge clk)begin #2;if(commit && !rst)begin
  reconstructed={n.phase+p.increment(committed_bin),n.sums[committed_bin*2],n.sums[committed_bin*2+1]};
  if(reconstructed!==p.states[committed_bin])$fatal(1,"single bank state differs at original commit cycle=%0d bin=%0d",cycle,committed_bin);
 end end
 end endgenerate
 task sample(input [23:0] value);begin
  wait(!pb);@(negedge clk);pcm=value;valid=1;@(negedge clk);valid=0;sample_number=sample_number+1;
 end endtask
 initial begin
  repeat(8)@(negedge clk);rst=0;
  for(i=0;i<8192;i=i+1)sample(i<2048?24'h7fffff:i<4096?24'h800000:(i*65537)^(i<<5));
  wait(!pb);@(negedge clk);if(results!=48)$fatal(1,"missing first48 band results %0d",results);
  for(repeat_reset=0;repeat_reset<4;repeat_reset=repeat_reset+1)for(target=1;target<=11;target=target+1)begin
   sample(24'h9142ac^target);wait(p.state==target);if(clk)@(negedge clk);rst=1;valid=1;repeat(2)@(negedge clk);rst=0;valid=0;
  end
  for(i=0;i<4096;i=i+1)sample((i*917617)^(i>>4));
  wait(!pb);repeat(4)@(negedge clk);if(results!=72)$fatal(1,"missing exact72 band outputs %0d",results);
  $display("PASS:12288 PCM samples/six complete2048-sample windows,72 exact band magnitudes and valid cycles, busy/PCM acceptance unchanged, every original112-bit state commit equal;44 mid-bin resets cover all11 processing states");$finish;
 end
 initial begin #25000000;$fatal(1,"DFT exact timeout samples=%0d",sample_number);end
endmodule

module tb_resource_log_exact;
 reg clk=0,rst=1;wire b,v;wire [4:0] i;wire [15:0] m;
 audio_dft12 n(.clk(clk),.rst(rst),.I_audio(24'd0),.I_audio_valid(1'b0),.busy(b),.O_band_valid(v),.O_band(i),.O_mag(m));
 ref_resource_audio_dft12 p(.clk(clk),.rst(rst),.I_audio(24'd0),.I_audio_valid(1'b0));
 reg [36:0] value,seed=37'h123456789;integer e,f,k;reg [31:0] phase_reference;
 task check(input [36:0] x);begin
  if(n.logarithm(x)!==p.logarithm(x))$fatal(1,"logarithm mismatch power=%h",x);
 end endtask
 initial begin
  check(0);
  for(e=0;e<37;e=e+1)for(f=0;f<64;f=f+1)begin
   value=(37'd1<<e)|((37'(f)<<(e>=6?e-6:0))&((37'd1<<e)-1));
   check(value);check(value|((37'd1<<(e>=6?e-6:0))-1));
  end
  for(k=0;k<262144;k=k+1)begin seed=(seed*37'd1664525+37'd1013904223);check(seed);end
  for(k=0;k<12;k=k+1)begin phase_reference=0;
   for(e=0;e<2048;e=e+1)begin
    if(phase_reference!==32'(e*n.increment(k)))$fatal(1,"phase product differs bin=%0d sample=%0d",k,e);
    phase_reference=phase_reference+n.increment(k);
   end
  end
  $display("PASS:37 leading-bit positions/all64 fractions/lower-bit edges plus262144 deterministic37-bit powers exactly match original logarithm;24576 phase states match repeated modulo32 addition");$finish;
 end
endmodule
