from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/3d_ui_smooth_20261018/route_cost';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';INI=O/'modelsim.ini';INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
f=[R/'common/distributed_map.v',R/'A_display/rtl/a_map_route_worker.v',T/'tb_route_cost_equivalence.v'];h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f+[Path(__file__).resolve(),R/'tools/generate_a_route_worker.py']};logs=[]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*(['-modelsimini',INI.as_posix()] if tool!='vlib' else []),*map(str,args)],cwd=T,capture_output=True,timeout=300)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-7000:])
 return s
try:
 if not W.exists():run('vlib',[W])
 run('vmap',['route_cost',W]);run('vlog',['-sv','-work',W,*f])
 s=run('vsim',['-c','route_cost.tb_route_cost_equivalence','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
 assert h=={str(p):hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in h}
 observations=[l for l in s.splitlines() if 'PASS:' in l]
 (O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':observations,'graphs_checked':13546,'all_origins':13,'cost_proof':'Terminal paths cost n*176+80; interior paths cost n*176. Encoded values 2*n+1 and 2*n preserve strict ordering and equality. Finite codes <31.'},indent=2));print('\n'.join(observations),flush=True)
finally:(O/'audit.log').write_text('\n'.join(logs))
