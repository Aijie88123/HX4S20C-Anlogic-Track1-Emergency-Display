from pathlib import Path
import re,json,hashlib,subprocess
R=Path(__file__).resolve().parents[1];O=R/'evidence/resource_timing_20261025/slices_exact';O.mkdir(parents=True,exist_ok=True)
F=R/'tests/reference_resource_timing';files=[R/'common/distributed_media.v',R/'common/raster_map_window.v',R/'B_control/rtl/distributed_media.v',R/'B_control/rtl/raster_map_window.v',F/'common_distributed_media.v',F/'common_raster_map_window.v',R/'tools/optimize_packet_slices.py',Path(__file__).resolve()]
codes=[]
for name,target,offset,count,data in [('distributed_media.v','pixels',0,6,'read_data[31:8]'),('raster_map_window.v','held',56,7,"{length[7:0]-8'd1,colour}")]:
 s=(R/'common'/name).read_text(encoding='utf-8-sig');original=(F/('common_'+name)).read_text(encoding='utf-8-sig')
 blocks=re.findall(r'case\(fill\)\s*\n(?:\s*3\x27d\d+:[^\n]+\n)+\s*endcase ',s)
 assert blocks and len(set(blocks))==1;block=blocks[0]
 old=f'{target}[{offset}+fill*24 +:24]<={data};' if target=='held' else 'pixels[fill*24 +: 24]<=read_data[31:8];'
 assert s.replace(block,old)==original,'Control/other data logic changed'
 for i in range(count):assert f"3'd{i}:{target}[{offset+i*24} +:24]<={data};" in block
 codes.append(block.replace(target+'[','frame[').replace('<=','='))
bench=O/'tb_slices.v';bench.write_text('''module tb_slices;
function [143:0] new_image;input[143:0] initial_frame;input[2:0]fill;input[31:0]read_data;reg[143:0]frame;begin frame=initial_frame;
'''+codes[0]+'''
new_image=frame;end endfunction
function [223:0] new_rle;input[223:0] initial_frame;input[2:0]fill;input[8:0]length;input[15:0]colour;reg[223:0]frame;begin frame=initial_frame;
'''+codes[1]+'''
new_rle=frame;end endfunction
reg[223:0] oldr,newr,initial_r;reg[143:0]oldi,newi;reg[31:0]data;reg[15:0]colour;reg[8:0]length;integer f,n,p,checks=0;
initial begin
 for(f=0;f<8;f=f+1)for(n=0;n<512;n=n+1)for(p=0;p<24;p=p+1)begin
  initial_r={32'h19283746,32'hf1a098bc,32'h9b1223aa,32'h42941400,32'h9f083145,32'hd1b00934,32'hbc381062}^(224'd1<<((n+p)%224));
  data=(32'd1<<p)^n;colour=p<16?(16'd1<<p):p==16?16'hffff:16'(n*257);length=n;
  oldi=initial_r[143:0];oldi[f*24+:24]=data[31:8];newi=new_image(initial_r[143:0],f,data);
  oldr=initial_r;oldr[56+f*24+:24]={length[7:0]-8'd1,colour};newr=new_rle(initial_r,f,length,colour);
  if(oldi!==newi || oldr!==newr)$fatal(1,"packet field rewrite changed fill=%0d n=%0d p=%0d",f,n,p);checks=checks+1;
 end
 $display("PASS:%0d complete144/224-bit packet comparisons, all8 fill values including out-of-range no-write, all512 length values, data/untouched-bit patterns; source restoration proves unchanged FSM and handshakes",checks);$finish;
end endmodule
''',encoding='utf-8');files.append(bench)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();h={str(p):sha(p) for p in files};M=Path('D:/modelsim/win64');W=O/'work';I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
def run(t,a):
 p=subprocess.run([str(M/(t+'.exe')),*[str(v).replace(chr(92),'/') for v in a]],cwd=O,capture_output=True,timeout=180)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6000:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['-modelsimini',I,'resource_slice',W]);run('vlog',['-modelsimini',I,'-sv','-work',W,bench]);s=run('vsim',['-modelsimini',I,'-c','resource_slice.tb_slices','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s;assert h=={str(p):sha(p) for p in files};obs=[v for v in s.splitlines() if 'PASS:' in v]
(O/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=h,observations=obs,scope='Actual generated write cases extracted from production sources and compared to frozen variable-index assignments; all remaining source text restored exactly.'),indent=2),encoding='utf-8');print('\n'.join(obs),flush=True)
