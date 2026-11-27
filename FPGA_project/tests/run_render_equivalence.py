from pathlib import Path
import subprocess,json,hashlib
r=Path(__file__).resolve().parents[1];o=r/'evidence/dynamic_smooth_R7_20261016/render_equivalence';o.mkdir(parents=True,exist_ok=True)
m=Path('D:/modelsim/win64');w=o/'work';ini=o/'modelsim.ini';ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
files=[r/'common/distributed_map.v',r/'B_control/rtl/emergency_map_top.v',r/'B_control/rtl/b_map_frame_renderer.v',r/'tests/baseline_R6/b_map_frame_renderer.v',r/'tests/tb_render_equivalence.v']
logs=[];observations=[]
def run(tool,args):
 p=subprocess.run([str(m/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=r/'tests',capture_output=True,timeout=300)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6000:])
 return s
try:
 if not w.exists():run('vlib',[w])
 run('vmap',['-modelsimini',ini,'window_rle',w]);run('vlog',['-modelsimini',ini,'-sv','-work',w,*files])
 s=run('vsim',['-modelsimini',ini,'-c','window_rle.tb_render_equivalence','-do','onerror {quit -code 1}; run -all; quit -code 0'])
 assert 'PASS:' in s;observations=[v for v in s.splitlines() if 'PASS:' in v];print('\n'.join(observations),flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':{str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in files},'observations':observations},indent=2))
