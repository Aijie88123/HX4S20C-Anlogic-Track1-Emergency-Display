from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import subprocess,sys,time,json
R=Path(__file__).resolve().parents[1];O=R/'evidence/flip_zoom_20261024/rechecks';O.mkdir(parents=True,exist_ok=True)
groups=[['run_photo_geometry.py','run_geometry_control_compat.py','run_four_fx.py','phase_four_fx_check.py'],
 ['run_prev_external_fades.py','run_visual_alignment.py','run_coldstart_video.py','run_startup_seamless.py'],
 ['run_control25_chain.py','run_boot_supervisor.py','run_boot_video720.py','run_tf_service_timing.py','run_eight_packed_transport.py']]
def branch(names):
 rows=[]
 for name in names:
  print('RUN '+name,flush=True);start=time.time()
  p=subprocess.run([sys.executable,'-X','utf8',str(R/'tests'/name)],cwd=R,capture_output=True,timeout=2400)
  s=(p.stdout+p.stderr).decode(errors='replace');(O/(name+'.log')).write_text(s,encoding='utf-8')
  if p.returncode:raise RuntimeError(name+'\n'+s[-8000:])
  rows.append(dict(script=name,status='PASS',seconds=round(time.time()-start,2),observations=[v for v in s.splitlines() if 'PASS:' in v]))
  print('PASS '+name,flush=True)
 return rows
with ThreadPoolExecutor(max_workers=3) as pool:rows=[r for group in pool.map(branch,groups) for r in group]
(O/'result.json').write_text(json.dumps(dict(status='PASS',tests=rows),indent=2),encoding='utf-8')
