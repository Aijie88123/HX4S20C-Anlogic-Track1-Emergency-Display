from pathlib import Path
import subprocess,sys,json,time
R=Path(__file__).resolve().parents[1];O=R/'evidence/audio_visual_20261021/regressions'
d=json.loads((O/'result.json').read_text());assert len(d['tests'])==15
names=['run_boot_supervisor.py','run_boot_video720.py','run_native_smooth.py','run_burst_concurrent.py','run_smooth_steady.py','run_coldstart_video.py','run_control25_chain.py']
for name in names:
 print('RECHECK '+name,flush=True);start=time.time()
 p=subprocess.run([sys.executable,str(R/'tests'/name)],cwd=R,capture_output=True,timeout=1500)
 s=(p.stdout+p.stderr).decode(errors='replace');(O/(name+'.log')).write_text(s,encoding='utf-8')
 if p.returncode:raise RuntimeError(name+'\n'+s[-7000:])
 row={'script':name,'status':'PASS','seconds':round(time.time()-start,2),'output':[v for v in s.splitlines() if 'PASS:' in v or 'MEASURE:' in v]}
 for i,old in enumerate(d['tests']):
  if old['script']==name:d['tests'][i]=row
 print('PASS '+name,flush=True)
d['final_startup_release_rechecks']=names
(O/'result.json').write_text(json.dumps(d,indent=2))
