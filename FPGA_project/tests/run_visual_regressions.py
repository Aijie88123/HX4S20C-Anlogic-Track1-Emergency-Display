from pathlib import Path
import subprocess,sys,json,time
R=Path(__file__).resolve().parents[1];O=R/'evidence/audio_visual_20261021/regressions';O.mkdir(parents=True,exist_ok=True)
names=['run_native_smooth.py','run_burst_wire.py','run_fast_window.py','run_smooth_steady.py','run_resource_equivalence.py','run_map_architecture.py','run_burst_concurrent.py','run_coldstart_video.py','run_eight_packed_transport.py','run_prev_external_fades.py','run_control25_chain.py','run_tf_service_timing.py','run_tf_first_response.py','run_dual_prev_controls.py','run_page_audio25.py']
rows=[]
for name in names:
 print('RUN '+name,flush=True);started=time.time()
 p=subprocess.run([sys.executable,str(R/'tests'/name)],cwd=R,capture_output=True,timeout=1500)
 s=(p.stdout+p.stderr).decode(errors='replace');(O/(name+'.log')).write_text(s,encoding='utf-8')
 if p.returncode:raise RuntimeError(name+'\n'+s[-7000:])
 rows.append({'script':name,'status':'PASS','seconds':round(time.time()-started,2),'output':[v for v in s.splitlines() if 'PASS:' in v or 'MEASURE:' in v]})
 print('PASS '+name,flush=True)
(O/'result.json').write_text(json.dumps({'status':'PASS','tests':rows},indent=2))
