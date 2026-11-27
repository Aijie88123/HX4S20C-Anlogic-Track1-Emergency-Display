from pathlib import Path
import subprocess,json,hashlib
r=Path(__file__).resolve().parents[1];m=Path('D:/modelsim/win64');o=r/'evidence/tf_load_recovery_20261015/recovery';o.mkdir(parents=True,exist_ok=True)
w=o/'work';ini=o/'modelsim.ini';ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
sources=[r/'common/ethernet_mdio.v',r/'common/raster_map_transport.v',r/'B_control/rtl/b_animation_cache.v',r/'tests/tb_endpoints.v',r/'tests/tb_r4_recovery.v']
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources};logs=[]
def run(tool,args):
 p=subprocess.run([str(m/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=r/'tests',capture_output=True,timeout=300)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-9000:])
 return s
try:
 if not w.exists():run('vlib',[w])
 run('vmap',['-modelsimini',ini,'r4_work',w])
 run('vlog',['-modelsimini',ini,'-sv','-work',w,*sources]);observations=[]
 for tb in ['tb_r4_phy_cache','tb_r4_raster']:
  s=run('vsim',['-modelsimini',ini,'-c','r4_work.'+tb,'-do','onerror {quit -code 1}; run -all; quit -code 0'])
  assert 'PASS:' in s;observations += [l for l in s.splitlines() if 'PASS:' in l];print('\n'.join(observations),flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'watchdog_test_cycles':64,'production_animation_watchdog_cycles':2500000,'observations':observations},indent=2))
