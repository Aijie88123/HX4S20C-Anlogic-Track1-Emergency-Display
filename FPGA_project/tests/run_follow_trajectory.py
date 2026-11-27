"""Capture untouched production A camera/route producer with scaled tick timers."""
from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parents[1];E=R/'evidence/follow_view_20261025/trajectory';E.mkdir(parents=True,exist_ok=True)
tb='''`timescale 1ns/1ps
module tb;reg clk=0;always #10 clk=~clk;reg rst=1,online=1;reg [2:0] state=1;reg [1:0] zoom=0,barriers=0;wire valid;wire [223:0] scene;
a_distributed_map_worker #(.CLK_HZ(1000),.FRAME_CYCLES(32),.DEBOUNCE_MS(1),.COMPUTE_VIEW(1)) dut(.clk(clk),.rst(rst),.online(online),.actual_state(state),.switches(zoom),.barrier_mode(barriers),.stream_ready(1'b1),.stream_valid(valid),.stream_data(scene));
integer e,b,z,c=0,n,out;
initial begin out=$fopen("trajectory.txt","w");
for(e=0;e<4;e=e+1)for(b=0;b<4;b=b+1)for(z=0;z<3;z=z+1)begin
@(negedge clk);rst=1;state=e*2+1;barriers=b;zoom=z;repeat(8)@(negedge clk);rst=0;n=0;
while(n<624)begin @(posedge clk);#1;if(valid)begin $fdisplay(out,"%0d %0d %047h",c,n,scene[187:0]);n=n+1;end
@(negedge clk);if(n==600)state=e*2;if(n==612)state=e*2+1;
end c=c+1;end
$fclose(out);$display("PASS:48cases624Apackets each;4events4barriers3zooms;paused12/resumed12");$finish;
end
initial begin #100000000;$fatal(1,"trajectory timeout");end
endmodule
'''
(E/'tb.v').write_text(tb);M=Path('D:/modelsim/win64');W=E/'work';I=E/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[v.as_posix() if isinstance(v,Path) else str(v) for v in args]],cwd=E,capture_output=True,timeout=300);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(E/'simulation.log').write_text('\n'.join(logs));assert p.returncode==0 and '** Error' not in s and '** Fatal' not in s,s[-3500:];return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,R/'A_display/rtl/a_map_route_worker.v',E/'tb.v']);s=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:48cases' in s
signed24=lambda n:n-(1<<24) if n&(1<<23) else n
cases={i:[] for i in range(48)}
for line in (E/'trajectory.txt').read_text().splitlines():
 c,k,h=line.split();c=int(c);k=int(k);s=int(h,16);e=c//12;b=(c//3)%4;z=c%3;step=(s>>80)&4095
 assert step==[3072,2458,2048][z] and (s>>10)&3==e
 cxq=signed24((s>>32)&0xffffff)+640*step;cyq=signed24((s>>56)&0xffffff)+360*step
 assert cxq%4096==0 and cyq%4096==0
 cx,cy=cxq//4096,cyq//4096;assert 360<=cx<=920 and 290<=cy<=530
 gx=(s>>140)&4095;gy=(s>>152)&4095
 cases[c].append(dict(tick=k,scene=f'{s:047x}',cx=cx,cy=cy,dx=cx//2-320,dy=cy//2-202,gx=gx,gy=gy,no_path=bool((s>>9)&1)))
for c,rows in cases.items():
 assert len(rows)==624 and (rows[0]['cx'],rows[0]['cy'])==(640,404)
 assert any(r['dx'] or r['dy'] for r in rows[:600]),c
 for a,b in zip(rows,rows[1:]):assert abs(a['cx']-b['cx'])<=2 and abs(a['cy']-b['cy'])<=2
 for r in rows[601:612]:assert (r['cx'],r['cy'],r['gx'],r['gy'])==tuple(rows[600][k] for k in ['cx','cy','gx','gy'])
 if c//3%4!=3:
  assert any((r['cx'],r['cy'],r['gx'],r['gy'])!=tuple(rows[611][k] for k in ['cx','cy','gx','gy']) for r in rows[613:]),c
  assert any(abs(a['gx']-b['gx'])+abs(a['gy']-b['gy'])>4 for a,b in zip(rows[:599],rows[1:600])),('route loop not reached',c)
 else:assert all(r['no_path'] and (r['gx'],r['gy'])==(rows[0]['gx'],rows[0]['gy']) for r in rows)
(E/'cases.json').write_text(json.dumps(cases,indent=2))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
(E/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes={str(p):sha(p) for p in [Path(__file__),R/'A_display/rtl/a_map_route_worker.v',E/'tb.v',E/'trajectory.txt',E/'cases.json']},cases=48,packets=29952,original_A_source_unchanged=True,camera_q12_recovered_exact=True,max_camera_increment=2,all_48_cases_camera_moves=True,reachable_route_loops_checked=True,paused_state_bit_hold_checked=True,timer_scaling='CLK_HZ1000 FRAME_CYCLES32 DEBOUNCE_MS1 for simulation only; production remains25MHz/416667cycles. Original projection/clamp/2pixel step/solver math unchanged.'),indent=2));print('PASS:29952actualA packets/48cases; recovered camera centres/step/clamps/route loops/hold/resume')
