from pathlib import Path
import subprocess,sys,json,time
R=Path(__file__).resolve().parents[1];O=R/'evidence/map_detail_20261020/regressions';O.mkdir(parents=True,exist_ok=True)
names=['run_coldstart_video.py','run_eight_packed_transport.py','run_dual_prev_controls.py','run_prev_external_fades.py','run_page_audio25.py','run_control25_chain.py','run_tf_service_timing.py','run_tf_first_response.py']
rows=[]
for name in names:
 print('RUN '+name,flush=True);start=time.time()
 p=subprocess.run([sys.executable,str(R/'tests'/name)],cwd=R,capture_output=True,timeout=1200)
 s=(p.stdout+p.stderr).decode(errors='replace');(O/(name+'.log')).write_text(s,encoding='utf-8')
 if p.returncode:raise RuntimeError(name+'\n'+s[-6000:])
 rows.append({'script':name,'status':'PASS','seconds':round(time.time()-start,2),'output':[l for l in s.splitlines() if 'PASS:' in l]})
 print('PASS '+name,flush=True)
(O/'result.json').write_text(json.dumps({'status':'PASS','tests':rows},indent=2))
