from pathlib import Path
import subprocess,sys,json,time
R=Path(__file__).resolve().parents[1];E=R/'evidence/follow_view_20261025/integration';E.mkdir(parents=True,exist_ok=True)
rows=[]
for name in ['run_native_smooth.py','run_smooth_steady.py']:
 start=time.time();print('RUN',name,flush=True)
 p=subprocess.run([sys.executable,'-X','utf8',str(R/'tests'/name)],cwd=R,capture_output=True,timeout=1500)
 s=(p.stdout+p.stderr).decode(errors='replace');(E/(name+'.log')).write_text(s,encoding='utf-8')
 assert p.returncode==0,s[-5000:]
 rows.append(dict(script=name,seconds=round(time.time()-start,1),status='PASS'));print(name,'PASS',flush=True)
(E/'index.json').write_text(json.dumps(rows,indent=2))
