from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parents[1];E=R/'evidence/uart_service_20261026/log';E.mkdir(parents=True,exist_ok=True);M=Path('D:/modelsim/win64');W=E/'work';I=E/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
files=[R/'B_control/rtl/maintenance_event_log.v',R/'tests/tb_uart_log.v']
def run(t,a):
 p=subprocess.run([str(M/(t+'.exe')),*[str(v).replace(chr(92),'/') for v in a]],cwd=E,capture_output=True,timeout=120);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(E/'audit.log').write_text('\n'.join(logs));assert p.returncode==0 and '** Error' not in s and '** Fatal' not in s,s[-5000:];return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files]);s=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_uart_log','-do','onerror {quit -code 1};run -all;quit -code 0']);assert 'PASS:' in s
(E/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files+[Path(__file__)]},observations=[s for s in s.splitlines() if 'PASS:' in s]),indent=2));print('PASS: event ring concurrency/reset test')
