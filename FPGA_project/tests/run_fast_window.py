from pathlib import Path
import subprocess,json,hashlib
r=Path(__file__).resolve().parents[1];o=r/'evidence/map_detail_20261020/cancel';o.mkdir(parents=True,exist_ok=True)
m=Path('D:/modelsim/win64');w=o/'work';ini=o/'modelsim.ini';ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
files=[r/'common/raster_map_transport.v',r/'common/raster_map_window.v',r/'tests/tb_fast_window_transport.v']
logs=[];observations=[]
def run(tool,args):
 p=subprocess.run([str(m/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=r/'tests',capture_output=True,timeout=300)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6000:])
 return s
try:
 if not w.exists():run('vlib',[w])
 run('vmap',['-modelsimini',ini,'window_rle',w]);run('vlog',['-modelsimini',ini,'-sv','-work',w,*files])
 for n,noise in [(60,0),(307200,0),(307200,1)]:
  s=run('vsim',['-modelsimini',ini,'-c','window_rle.tb_fast_window_transport','-gN='+str(n),'-gNOISE='+str(noise),'-do','onerror {quit -code 1}; run -all; quit -code 0'])
  assert 'PASS:' in s;rows=[v for v in s.splitlines() if 'PASS:' in v];observations+=rows;print('\n'.join(rows),flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':{str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in files},'observations':observations},indent=2))
