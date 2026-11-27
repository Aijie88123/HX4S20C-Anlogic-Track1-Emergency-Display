from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parents[1];O=R/'evidence/scan_trace_20261024/solid';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
files=[R/'A_display/rtl/smart_terminal_hw_top.v',R/'A_display/vendor/user_source/hdl_source/video_rgb_to_axis_720p.v',R/'tests/tb_scan_diagnostic.v',Path(__file__).resolve()]
h={p.as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
def run(t,args):
 p=subprocess.run([str(M/(t+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=O,capture_output=True,timeout=900)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-7000:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['-modelsimini',I,'scan_diagnostic',W]);run('vlog',['-modelsimini',I,'-sv','-work',W,*files[:-1]])
s=run('vsim',['-modelsimini',I,'-c','scan_diagnostic.tb_scan_diagnostic','-do','onerror {quit -code 1}; run -all; quit -code 0'])
obs=[v for v in s.splitlines() if 'PASS:' in v];assert len(obs)==1
assert h=={p.as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
(O/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=h,observations=obs,scope='128+ complete pure-color frames, edge coordinates, normal and disabled bypass, real AXIS converter and startup guard; no TF commit or SDRAM-ready required. HDMI sink/serializer and physical board are not simulated.'),indent=2),encoding='utf-8')
print('\n'.join(obs),flush=True)
