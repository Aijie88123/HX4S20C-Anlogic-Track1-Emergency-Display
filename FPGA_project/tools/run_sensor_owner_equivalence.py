from pathlib import Path
import json,hashlib,subprocess
R=Path(__file__).resolve().parents[1];E=R/'evidence/ds18b20_console_20261029/owner_equivalence';E.mkdir(exist_ok=True);M=Path('D:/modelsim/win64');W=E/'work';I=E/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
files=[R/'common/dual_board_emergency_control.v',R/'tests/fixtures/sensor_owner_folded_reference.v',R/'tests/tb_sensor_owner_equivalence.sv'];logs=[]
def run(t,a):
 p=subprocess.run([str(M/(t+'.exe')),*[str(x).replace(chr(92),'/') for x in a]],cwd=E,capture_output=True,timeout=120);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(E/'audit.log').write_text('\n'.join(logs));assert p.returncode==0 and '** Error' not in s and '** Fatal' not in s,s[-5000:];return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files]);s=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_sensor_owner_equivalence','-do','onerror {quit -code 1};run -all;quit -code 0']);assert 'PASS:' in s
bound=files+[Path(__file__),R/'A_display/rtl/dual_board_emergency_control.v',R/'B_control/rtl/dual_board_emergency_control.v']
(E/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest().upper() for p in bound},observations=[v for v in s.splitlines() if 'PASS:' in v],scope='Cycle-exact observable state/ownership equivalence against actual previously verified guarded RTL; not a formal proof or physical timing test.'),indent=2));print('\n'.join(v for v in s.splitlines() if 'PASS:' in v))
