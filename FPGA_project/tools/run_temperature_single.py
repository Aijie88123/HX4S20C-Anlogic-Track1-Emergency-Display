from pathlib import Path
import subprocess,hashlib,json
R=Path(__file__).resolve().parents[1];E=R/'evidence/temperature_single_20261031/policy';E.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=E/'work';I=E/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
files=[R/'B_control/rtl/temperature_alarm.v',R/'tests/tb_temperature_single.sv'];h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper();bound=files+[Path(__file__)];before={str(p):h(p) for p in bound};logs=[]
def run(name,args):
 p=subprocess.run([str(M/(name+'.exe')),*[str(a).replace(chr(92),'/') for a in args]],cwd=E,capture_output=True,timeout=180)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(E/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 assert p.returncode==0 and '** Error' not in s and '** Fatal' not in s,s[-5000:]
 return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files]);cases=[]
for hz in [1000000,25000000]:
 s=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_temperature_single','-gCLK_HZ='+str(hz),'-do','onerror {quit -code 1}; run -all; quit -code 0']);observations=[x for x in s.splitlines() if 'PASS:' in x];assert observations;cases+=observations
assert before=={str(p):h(p) for p in bound}
(E/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=before,cases=cases,physical_test=False),indent=2),encoding='utf-8');print('\n'.join(cases))
