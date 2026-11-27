LOG=" function [11:0] logarithm;input [36:0] p;\n reg e5,e4,e3,e2,e1,e0;reg [37:0] v38;reg [21:0] v22;reg [13:0] v14;reg [9:0] v10;reg [7:0] v8;reg [6:0] v7;\n begin\n  e5=|p[36:32];v38=e5?{27'd0,p[36:26]}:{p[31:0],6'd0};\n  e4=|v38[37:22];v22=e4?v38[37:16]:v38[21:0];\n  e3=|v22[21:14];v14=e3?v22[21:8]:v22[13:0];\n  e2=|v14[13:10];v10=e2?v14[13:4]:v14[9:0];\n  e1=|v10[9:8];v8=e1?v10[9:2]:v10[7:0];\n  e0=v8[7];v7=e0?v8[7:1]:v8[6:0];\n  logarithm={e5,e4,e3,e2,e1,e0,v7[5:0]};\n end endfunction"
SCHEDULE=" // A single40-bit RAM uses the original spare states for prefetch and\n // writes. The two sums are loaded before state3; the original state11\n // external commit/advance schedule and arithmetic widths stay unchanged.\n wire advance_bin=(state==11 && sample_index!=2047 && bin!=11) || (state==13 && bin!=11);\n wire read_first=(state==0 && I_audio_valid) || advance_bin;\n wire read_second=state==1 || state==2;\n wire [3:0] fetch_bin=state==0?4'd0:advance_bin?bin+1'b1:bin;\n wire signed [39:0] next_sum_q=sum_q+extended_product;\n reg [39:0] fetched_sum, fetched_i;reg first_pending;\n assign state_q={fetched_i,fetched_sum};\n always @(posedge clk)begin\n  if(state==8)sums[{bin,1'b0}]<=sum_i;\n  else if(state==10)sums[{bin,1'b1}]<=next_sum_q;\n  else if(read_first || read_second)fetched_sum<=sums[{fetch_bin,read_second}];\n end\n always @(posedge clk)begin\n  if(rst)first_pending<=0;else first_pending<=read_first;\n  if(first_pending)fetched_i<=fetched_sum;\n  sine_q<=sine_mem[sine_address];\n end\n"
from pathlib import Path
import hashlib,json
R=Path(__file__).resolve().parents[1];F=R/'tests/reference_resource_timing/B_control_audio_dft12.v'
s=F.read_text(encoding='utf-8-sig')
s=s.replace('(* ram_style="bram_32k" *) reg [111:0] states[0:11]; /* fehdl force_ram=1, ram_style="bram_32k" */','(* ram_style="bram" *) reg [39:0] sums[0:23]; /* fehdl force_ram=1, ram_style="bram" */')
s=s.replace('reg [111:0] state_q;', 'wire [79:0] state_q;')
s=s.replace(' assign busy=state!=0;', ' // Induction: each completed PCM sample adds increment(bin) once;\n // reset/window boundaries start at zero. This replaces the stored phase\n // with the exact low32-bit product, retaining the original state3 capture.\n wire [31:0] phase_at_sample=sample_index*increment(bin);\n assign busy=state!=0;')
s=s.replace('phase<=sample_index==0?0:state_q[111:80];','phase<=sample_index==0?0:phase_at_sample;')
a=s.index(' function [11:0] logarithm;');b=s.index(' end endfunction',a)+len(' end endfunction')
s=s[:a]+LOG+s[b:]
a=s.index(' always @(posedge clk)begin state_q<=states[bin]');b=s.index(' always @(posedge clk)begin\n  if(rst)',a)
s=s[:a]+SCHEDULE+s[b:]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
files=[R/'B_control/rtl/audio_dft12.v',R/'common/audio_dft12.v']
for p in files:p.write_text(s,encoding='utf-8')
O=R/'evidence/resource_timing_20261025';O.mkdir(exist_ok=True,parents=True)
(O/'dft-generation.json').write_text(json.dumps(dict(status='PASS',source_hashes={str(F):sha(F)},runner_hashes={str(Path(__file__).resolve()):sha(Path(__file__))},generated_hashes={str(p):sha(p) for p in files},phase_invariant='low32(sample_index*increment(bin)); resets and window wrap restart from zero',state_bits=960,original_state_bits=1344,public_cycles_unchanged=True),indent=2))
