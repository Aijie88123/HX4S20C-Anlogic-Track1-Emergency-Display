from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parents[1];O=R/'evidence/scan_trace_20261024/native_hdmi';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
files=list(Path('D:/td_extract/5E781D7/sim_release/eg4').glob('*.v'))+[R/'A_display/vendor/user_source/hdl_source/hdmi1.4b_transmitter_core/hdmi_1_4b_transmitter_core_wrapper.enc.v',R/'A_display/vendor/user_source/hdl_source/video_rgb_to_axis_720p.v',R/'tests/tb_hdmi_native_scan.v']
bound=files+[Path(__file__).resolve()];h={p.as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in bound}
def run(t,args):
 p=subprocess.run([str(M/(t+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=O,capture_output=True,timeout=1200)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-9000:])
 return s
report=dict(status='FAIL',source_hashes=h,scope='Unmodified production encrypted HDMI core, original720p timings, AXIS converter and independent TMDS data decode. Digital core simulation; no serializer, cable or real sink electrical model.')
try:
 if not W.exists():run('vlib',[W])
 run('vmap',['-modelsimini',I,'hdmi_native_scan',W])
 run('vlog',['-modelsimini',I,'-vlog01compat','-work',W,*[p for p in files if 'sim_release' in p.parts]])
 run('vlog',['-modelsimini',I,'-sv','-work',W,*[p for p in files if 'sim_release' not in p.parts and p.name!='hdmi_1_4b_transmitter_core_wrapper.enc.v']])
 run('vlog',['-modelsimini',I,'-vlog01compat','-work',W,*[p for p in files if p.name=='hdmi_1_4b_transmitter_core_wrapper.enc.v']])
 s=run('vsim',['-modelsimini',I,'-c','-l',O/'live.log','hdmi_native_scan.tb_hdmi_native_scan','-do','onerror {quit -code 1}; run -all; quit -code 0'])
 obs=[v for v in s.splitlines() if 'PASS:' in v or 'TRACE:' in v];assert any('PASS:' in v for v in obs)
 assert h=={p.as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in bound}
 report.update(status='PASS',observations=obs);print('\n'.join(obs),flush=True)
except Exception as e:report['error']=str(e);raise
finally:(O/'result.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
