from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import subprocess, sys, json, time
R=Path(__file__).resolve().parents[1]
O=R/'evidence/audio_visual_seamless_20261022/final_rechecks'
O.mkdir(parents=True,exist_ok=True)
# The native chain creates fixtures read by steady/concurrent: keep that
# dependency sequential. Other libraries/logs/fixtures are independent.
groups=[['run_control25_chain.py'],
 ['run_native_smooth.py','run_smooth_steady.py','run_burst_concurrent.py'],
 ['run_boot_supervisor.py','run_boot_video720.py','run_startup_seamless.py','run_coldstart_video.py']]
def branch(names):
 rows=[]
 for name in names:
  print('RUN '+name,flush=True);start=time.time()
  p=subprocess.run([sys.executable,str(R/'tests'/name)],cwd=R,capture_output=True,timeout=1800)
  s=(p.stdout+p.stderr).decode(errors='replace')
  (O/(name+'.log')).write_text(s,encoding='utf-8')
  if p.returncode:raise RuntimeError(name+'\n'+s[-6500:])
  rows.append(dict(script=name,status='PASS',seconds=round(time.time()-start,2),
   output=[v for v in s.splitlines() if 'PASS:' in v or 'MEASURE:' in v]))
  print('PASS '+name,flush=True)
 return rows
with ThreadPoolExecutor(max_workers=3) as pool:
 rows=[row for result in pool.map(branch,groups) for row in result]
(O/'result.json').write_text(json.dumps(dict(status='PASS',tests=rows,
 reason='Rechecked final local reference-clock diagnostics reset release; no clock/pin constraints changed'),indent=2),encoding='utf-8')
p=R/'evidence/audio_visual_20261021/regressions/result.json'
d=json.loads(p.read_text());replacements={v['script']:v for v in rows}
d['tests']=[replacements.get(v['script'],v) for v in d['tests']]
d['final_startup_source_rechecks']='evidence/audio_visual_seamless_20261022/final_rechecks/result.json'
p.write_text(json.dumps(d,indent=2),encoding='utf-8')
