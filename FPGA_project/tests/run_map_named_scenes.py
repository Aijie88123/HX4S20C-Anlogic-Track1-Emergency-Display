from pathlib import Path
import subprocess,json,hashlib,importlib.util
R=Path(__file__).resolve().parents[1];P=Path('D:/HX4S20C_flip_zoom_20261024');O=R/'evidence/map_abc_20261025/named_scenes';O.mkdir(parents=True,exist_ok=True)
original=P/'A_display/rtl/a_map_route_worker.v';reference=O/'reference_route_worker.v'
reference.write_text(original.read_text(encoding='utf-8-sig').replace('a_campus_route_solver','reference_campus_route_solver').replace('a_distributed_map_worker','reference_distributed_map_worker'),encoding='utf-8')
subprocess.run(['C:/Users/jerry/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe',str(R/'tools/generate_map_scene_parameters.py'),'--check'],check=True)
spec=importlib.util.spec_from_file_location('named',R/'tools/resolve_map_scene.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
checks=0;vectors=[]
for code in range(256):
 for mode in range(4):
  name=chr(code)
  try:d=module.resolve(name,mode)
  except ValueError:assert name not in 'ABC'
  else:
   index='ABC'.index(name);assert d['event_code']==index and d['actual_state']==index*2+1 and d['barrier_mode']==mode and d['allowed_exit_nodes']==[9,10,11,12]
  checks+=1
for name in 'ABC':
 for mode in range(4):
  d=module.resolve(name,mode);vectors.append((d['barrier_mode']<<3)|d['actual_state'])
for bad in ['','AB','A/B/C']:
 try:module.resolve(bad,0)
 except ValueError:pass
 else:raise AssertionError('invalid alias accepted')
for bad in [-1,4]:
 try:module.resolve('A',bad)
 except ValueError:pass
 else:raise AssertionError('invalid barrier accepted')
fixture=O/'scene_controls.hex';fixture.write_text(''.join(f'{v:02x}\n' for v in vectors),encoding='utf-8')
files=[R/'A_display/rtl/a_map_route_worker.v',reference,R/'tests/tb_map_named_scenes.v']
bound=files+[fixture,R/'assets/map_scene_presets.json',R/'assets/map_scene_parameters.json',R/'tools/generate_map_scene_parameters.py',R/'tools/resolve_map_scene.py',Path(__file__).resolve()]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();h={str(p):sha(p) for p in bound}
M=Path('D:/modelsim/win64');I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');W=O/'work';logs=[]
def run(t,a):
 p=subprocess.run([str(M/(t+'.exe')),*[str(v).replace(chr(92),'/') for v in a]],cwd=O,capture_output=True,timeout=600)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6000:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['-modelsimini',I,'named_scenes',W]);run('vlog',['-modelsimini',I,'-sv','-work',W,*files])
s=run('vsim',['-modelsimini',I,'-c','named_scenes.tb_map_named_scenes','-do','onerror {quit -code 1}; run -all; quit -code 0'])
assert 'PASS:' in s;assert h=={str(p):sha(p) for p in bound}
obs=[f'PASS: {checks} ASCII-name/live-barrier lookups; invalid names/levels rejected']+[v for v in s.splitlines() if 'PASS:' in v]
(O/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=h,reference_source_hashes={str(original):sha(original)},observations=obs,scope='Parameter-layer API resolves names before canonical V12 controls. Real resolver vectors drive unchanged production route worker across48 cases and compare expected controls. No new RTL or firmware.'),indent=2),encoding='utf-8')
print('\n'.join(obs),flush=True)
