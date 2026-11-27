from pathlib import Path
import subprocess,json,hashlib,shutil
R=Path(__file__).resolve().parents[1];O=R/'evidence/particle_transition_20261031/manual';O.mkdir(parents=True,exist_ok=True)
probe=R/'evidence/particle_transition_20261031/simulation/particle_transition_probe.v'
M=Path('D:/modelsim/win64');W=O/'work';I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
files=[R/'A_display/rtl'/n for n in ['a_media_cached_control.v','video_scanout_720p.v','distributed_media.v','dynamic_rgb444.v','map_received_scanout.v']]+[R/'A_display/vendor/user_source/hdl_source/SD/sd_card_bmp.v',probe,R/'tests/tb_particle_manual_control.v',R/'tests/tb_particle_commit_cdc.v']
bound=files+[R/'tools/run_particle_transition.py',R/'A_display/rtl/smart_terminal_hw_top.v',Path(__file__).resolve()]
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper();hashes={str(p):h(p) for p in bound}
def run(t,a):
 p=subprocess.run([str(M/(t+'.exe')),*[str(v).replace(chr(92),'/') for v in a]],cwd=O,capture_output=True,timeout=900)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-7500:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['-modelsimini',I,'particle_manual',W]);run('vlog',['-modelsimini',I,'-sv','-work',W,*files])
s=''
for name in ['tb_particle_manual_control','tb_particle_commit_cdc']:s+=run('vsim',['-modelsimini',I,'-c','particle_manual.'+name,'-do','onerror {quit -code 1}; run -all; quit -code 0'])
assert s.count('PASS:')==3;assert hashes=={str(p):h(p) for p in bound}
obs=[v for v in s.splitlines() if 'PASS:' in v]
(O/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=hashes,observations=obs,scope='Actual A cached scheduler and debounced short key pulses, original160ms manual fade at scaled100kHz clock; complete role metadata modeled. Verbatim top transition/cache source coordination under forced shortened frame timing; no pixel/physical proof.'),indent=2),encoding='utf-8');print('\n'.join(obs))
