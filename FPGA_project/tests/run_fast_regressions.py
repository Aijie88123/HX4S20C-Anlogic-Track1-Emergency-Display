from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import subprocess,sys,time,json
R=Path(__file__).resolve().parents[1];O=R/'evidence/fast_carousel_20261025/regressions';O.mkdir(parents=True,exist_ok=True)
groups=[['run_photo_geometry.py','run_geometry_control_compat.py','run_four_fx.py','run_prev_external_fades.py','run_visual_alignment.py','run_eight_packed_transport.py','run_dual_prev_controls.py','run_fast_period_top.py'],
        ['run_scan_qualified.py','run_scan_native_link.py','run_map_partition.py']]
if '--resume-compositor' in sys.argv:groups=[groups[0][2:]]
if '--resume-controls' in sys.argv:groups=[groups[0][6:]]
def branch(names):
 rows=[]
 for name in names:
  print('RUN '+name,flush=True);start=time.time()
  p=subprocess.run([sys.executable,'-X','utf8',str(R/'tests'/name)],cwd=R,capture_output=True,timeout=2400)
  s=(p.stdout+p.stderr).decode(errors='replace');(O/(name+'.log')).write_text(s,encoding='utf-8')
  if p.returncode:raise RuntimeError(name+'\n'+s[-7000:])
  rows.append(dict(script=name,status='PASS',seconds=round(time.time()-start,2),observations=[v for v in s.splitlines() if 'PASS:' in v]));print('PASS '+name,flush=True)
 return rows
with ThreadPoolExecutor(max_workers=2) as pool:rows=[r for group in pool.map(branch,groups) for r in group]
(O/'result.json').write_text(json.dumps(dict(status='PASS',tests=rows),indent=2),encoding='utf-8')
