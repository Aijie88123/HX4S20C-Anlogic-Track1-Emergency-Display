from pathlib import Path
import subprocess,hashlib,json
r=Path(__file__).resolve().parents[1];m=Path('D:/modelsim/win64');o=r/'evidence/map_render_B_20261014/transport';o.mkdir(parents=True,exist_ok=True);w=o/'work'
f=[r/'common/raster_map_transport.v',r/'tests/tb_rle_transport.v'];h={str(p.relative_to(r)):hashlib.sha256(p.read_bytes()).hexdigest() for p in f};logs=[]
def run(tool,args):
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=r/'tests',capture_output=True,timeout=300);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-4500:])
 return s
try:
 if not w.exists():run('vlib',[str(w)])
 run('vmap',['rle_work',str(w)]);run('vlog',['-sv','-work',str(w),*map(str,f)])
 for n,noise in [(60,0),(230400,0),(230400,1)]:
  s=run('vsim',['-c','rle_work.tb_rle_transport','-gN='+str(n),'-gNOISE='+str(noise),'-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s;print('\n'.join(x for x in s.splitlines() if 'PASS:' in x),flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p.relative_to(r)):hashlib.sha256(p.read_bytes()).hexdigest() for p in f};(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h},indent=2))
