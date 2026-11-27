from pathlib import Path
import subprocess,hashlib,json
R=Path(__file__).resolve().parents[1];O=R/'evidence/flip_zoom_20261024/control_compat';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
files=[R/'A_display/rtl/video_scanout_720p.v',R/'A_display/rtl/distributed_media.v',R/'tests/reference_geometry/parent_scanout.v',R/'tests/reference_geometry/parent_unpack.v',R/'tests/tb_photo_geometry_control.v',R/'tests/tb_geometry_compat.v',Path(__file__).resolve()]
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
def run(t,a):
 p=subprocess.run([str(M/(t+'.exe')),*[v.as_posix() if isinstance(v,Path) else str(v) for v in a]],cwd=O,capture_output=True,timeout=900)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-9000:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['-modelsimini',I,'geometry_control_compat',W]);run('vlog',['-modelsimini',I,'-sv','-work',W,*files[:-1]])
obs=[]
for top in ['tb_photo_geometry_control','tb_geometry_compat']:
 s=run('vsim',['-modelsimini',I,'-c','geometry_control_compat.'+top,'-do','onerror {quit -code 1}; run -all; quit -code 0'])
 obs.extend(v for v in s.splitlines() if 'PASS:' in v)
assert len(obs)==2
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
(O/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=h,observations=obs),indent=2),encoding='utf-8')
print('\n'.join(obs),flush=True)
