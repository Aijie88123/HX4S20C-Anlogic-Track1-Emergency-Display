from pathlib import Path
import subprocess,json,zlib,hashlib,sys
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/distributed_complete_20261012/network';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work'
files=list((R/'common').glob('*.v'))+[T/n for n in ['tb_endpoints.v','tb_distributed_endpoints.v','tb_distributed_frames.v']]+[Path('D:/td_extract/5E781D7/sim_release/eg4/eg_logic_io.v')]
before={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
logs=[];results=[]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*args],cwd=T,capture_output=True,timeout=120)
 log=(p.stdout+p.stderr).decode(errors='replace');logs.append(log)
 if p.returncode or '** Error' in log or '** Fatal' in log:raise RuntimeError(log)
 return log
if not W.exists():run('vlib',[str(W)])
run('vlog',['-sv','-work',str(W),*map(str,files)])
for top,delay in [('tb_distributed_frames',None)]+[('tb_distributed_endpoints',i) for i in [1,2,3]]:
 args=['-c','-novopt','-t','1ps','-lib',str(W),top]
 if delay:args+=['glbl','-gRX_DELAY='+str(delay)]
 log=run('vsim',args+['-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in log
 (O/(top+str(delay)+'.log')).write_text(log);results.extend(l for l in log.splitlines() if 'PASS:' in l)
for name,continuous in [('distributed_core_tx_nibbles.hex',True),('distributed_endpoint_tx_nibbles.hex',False)]:
 s=(T/name).read_text().strip();frames=[s[i:i+144] for i in range(0,len(s),144)] if continuous else s.splitlines()
 assert frames
 for n in frames:
  b=bytes(int(n[i+1]+n[i],16) for i in range(0,len(n),2));f=b[8:]
  assert len(f)==64 and b[:8]==bytes.fromhex('55555555555555d5') and f[12:17]==bytes.fromhex('88b5485802')
  assert int.from_bytes(f[-4:],'little')==zlib.crc32(f[:-4])
 results.append('PASS: independent Python zlib FCS '+name+' frames='+str(len(frames)))
assert before=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
(O/'result.json').write_text(json.dumps({'status':'PASS','observations':results,'compiled_sources':before},indent=2));print(json.dumps(results))
