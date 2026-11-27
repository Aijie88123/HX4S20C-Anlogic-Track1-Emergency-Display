from pathlib import Path
import hashlib,json,subprocess
R=Path(__file__).resolve().parents[1];E=R/'evidence/ds18b20_console_20261029/ownership';E.mkdir(parents=True,exist_ok=True);M=Path('D:/modelsim/win64');W=E/'work';I=E/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
files=[R/'common/dual_board_emergency_control.v',R/'tests/tb_sensor_owner.sv'];copies=[R/b/'rtl/dual_board_emergency_control.v' for b in ['A_display','B_control']];assert all(p.read_bytes()==files[0].read_bytes() for p in copies)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper();h={str(p):sha(p) for p in files+copies+[Path(__file__)]};logs=[]
def run(t,args):
 p=subprocess.run([str(M/(t+'.exe')),*[str(a).replace(chr(92),'/') for a in args]],cwd=E,capture_output=True,timeout=120);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(E/'audit.log').write_text('\n'.join(logs),encoding='utf-8');assert p.returncode==0 and '** Error' not in s and '** Fatal' not in s,s[-6000:];return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files]);s=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_sensor_owner','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
assert h=={str(p):sha(p) for p in files+copies+[Path(__file__)]}
(E/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=h,observations=[v for v in s.splitlines() if 'PASS:' in v],scope='Actual A production controller and byte-identical B/common copies; local ownership/event cannot be claimed by a new remote FIRE, including in-flight and heartbeat cases; original normal remote behavior and explicit local exit retained.'),indent=2),encoding='utf-8');print('\n'.join(v for v in s.splitlines() if 'PASS:' in v))
