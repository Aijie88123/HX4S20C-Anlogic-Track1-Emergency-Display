from pathlib import Path
import subprocess,hashlib,json
R=Path(__file__).resolve().parents[1];O=R/'evidence/fast_carousel_20261025/continuous17';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
files=[R/'A_display/rtl/video_scanout_720p.v',R/'A_display/rtl/distributed_media.v',R/'tests/tb_fast_geometry_continuous.v',Path(__file__).resolve()]
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
def run(t,a):
 p=subprocess.run([str(M/(t+'.exe')),*[v.as_posix() if isinstance(v,Path) else str(v) for v in a]],cwd=O,capture_output=True,timeout=900)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-9000:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['-modelsimini',I,'photo_geometry',W]);run('vlog',['-modelsimini',I,'-sv','-work',W,*files[:-1]])
s=run('vsim',['-modelsimini',I,'-c','photo_geometry.tb_fast_geometry_continuous','-do','onerror {quit -code 1}; run -all; quit -code 0'])
obs=[v for v in s.splitlines() if 'PASS:' in v];assert len(obs)==1,s[-8000:]
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
(O/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=h,observations=obs,scope='Continuous actual controller and scanout/row reader/fast RGB888 unpack, full flip/zoom progressions and normal-to-geometry-to-normal FIFO handoffs, nonuniform immutable source slots and latest-source queuing. Behavioral FIFO, no analog model.'),indent=2),encoding='utf-8')
print('\n'.join(obs),flush=True)
