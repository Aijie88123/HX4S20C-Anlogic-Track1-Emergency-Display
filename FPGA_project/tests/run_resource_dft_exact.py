from pathlib import Path
import re,subprocess,hashlib,json,sys
R=Path(__file__).resolve().parents[1];F=R/'tests/reference_resource_timing/B_control_audio_dft12.v'
C=Path(sys.argv[1]) if len(sys.argv)>1 else R/'B_control/rtl/audio_dft12.v'
O=Path('D:/_fpga_package_tools/resource_timing_20261025')/('dft_trial_'+C.stem) if len(sys.argv)>1 else R/'evidence/resource_timing_20261025/dft_exact';O.mkdir(parents=True,exist_ok=True)
P=O/'reference_dft.v';P.write_text(re.sub(r'\baudio_dft12\b','ref_resource_audio_dft12',F.read_text(encoding='utf-8-sig')),encoding='utf-8')
files=[C,P,R/'tests/tb_resource_dft_exact.v'];bound=files+[F,Path(__file__).resolve()];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();h={str(p):sha(p) for p in bound}
M=Path('D:/modelsim/win64');I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');W=O/'work';logs=[]
def run(t,a):
 p=subprocess.run([str(M/(t+'.exe')),*[str(v).replace(chr(92),'/') for v in a]],cwd=O,capture_output=True,timeout=900)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6500:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['-modelsimini',I,'resource_dft',W]);run('vlog',['-modelsimini',I,'-sv','-work',W,*files])
s=run('vsim',['-modelsimini',I,'-c','-l',O/'live.log','resource_dft.tb_resource_dft_exact','-gLAYOUT='+(sys.argv[2] if len(sys.argv)>2 else '2'),'-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
s+=run('vsim',['-modelsimini',I,'-c','-l',O/'log_exact.log','resource_dft.tb_resource_log_exact','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s;assert h=={str(p):sha(p) for p in bound}
obs=[v for v in s.splitlines() if 'PASS:' in v];(O/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=h,observations=obs),indent=2),encoding='utf-8');print('\n'.join(obs),flush=True)
