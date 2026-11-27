from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import subprocess,sys,time,json
R=Path(__file__).resolve().parents[1];O=R/'evidence/resource_timing_20261025/regressions';O.mkdir(parents=True,exist_ok=True)
groups=[['run_resource_roms.py','run_resource_dft_exact.py','run_resource_slices.py','run_audio_visual.py','run_visual_alignment.py','run_startup_seamless.py','run_fast_period_top.py'],['run_native_smooth.py','run_smooth_steady.py','run_burst_concurrent.py','run_eight_packed_transport.py','run_control25_chain.py','run_scan_native_link.py']]
def branch(names):
 rows=[]
 for name in names:
  print('RUN '+name,flush=True);start=time.time()
  p=subprocess.run([sys.executable,'-X','utf8',str(R/'tests'/name)],cwd=R,capture_output=True,timeout=2700)
  text=(p.stdout+p.stderr).decode(errors='replace');(O/(name+'.log')).write_text(text,encoding='utf-8')
  if p.returncode:raise RuntimeError(name+'\n'+text[-6500:])
  rows.append(dict(script=name,status='PASS',seconds=round(time.time()-start,2),observations=[v for v in text.splitlines() if 'PASS:' in v]));print('PASS '+name,flush=True)
 return rows
with ThreadPoolExecutor(max_workers=2) as pool:rows=[r for group in pool.map(branch,groups) for r in group]
(O/'result.json').write_text(json.dumps(dict(status='PASS',tests=rows),indent=2),encoding='utf-8')
