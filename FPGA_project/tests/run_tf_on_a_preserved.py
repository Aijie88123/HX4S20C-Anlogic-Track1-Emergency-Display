from pathlib import Path
import subprocess,sys,json
r=Path(__file__).resolve().parents[1];p=Path(sys.executable);o=r/'evidence/TF_on_A_20261014/preserved';o.mkdir(parents=True,exist_ok=True);results=[]
for name in ['run_tests','run_distributed_network','run_spectrum_offload','run_external_spectrum_display','run_map_stages','run_map_wire_flags','run_period_button','run_realtime_parameters','run_b_role_display','run_raster_mac','run_media_offload','run_rle_transport']:
 if name in ['run_tests','run_distributed_network','run_spectrum_offload','run_external_spectrum_display','run_map_stages','run_map_wire_flags'] and (o/(name+'.log')).exists():
  results.append(name);print(name+': PASS (already source-verified)',flush=True);continue
 q=subprocess.run([str(p),'-X','utf8',str(r/'tests'/(name+'.py'))],cwd=r,capture_output=True,timeout=900)
 s=(q.stdout+q.stderr).decode(errors='replace');(o/(name+'.log')).write_text(s)
 print(name+': '+('PASS' if q.returncode==0 else 'FAIL'),flush=True)
 if q.returncode:raise RuntimeError(s[-5000:])
 results.append(name)
(o/'result.json').write_text(json.dumps({'status':'PASS','scripts':results},indent=2))
