from pathlib import Path
import subprocess,json,hashlib,binascii,numpy as np
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[1];E=R/'evidence/uart_subtitle_20261026/bridge';E.mkdir(parents=True,exist_ok=True)
files=[R/'B_control/rtl/maintenance_uart.v',R/'B_control/rtl/uart_subtitle_bridge.v',R/'tests/tb_subtitle_bridge.v']
M=Path('D:/modelsim/win64');W=E/'work';I=E/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
def run(t,args):
 p=subprocess.run([str(M/(t+'.exe')),*[str(v).replace(chr(92),'/') for v in args]],cwd=E,capture_output=True,timeout=300);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(E/'audit.log').write_text('\n'.join(logs));assert p.returncode==0 and '** Error' not in s and '** Fatal' not in s,s[-5000:];return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files]);log=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_subtitle_bridge','-do','onerror {quit -code 1};run -all;quit -code 0']);assert 'PASS:' in log
inputs=files+[Path(__file__)]
(E/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},observations=[s for s in log.splitlines() if 'PASS:' in s],hardware_test=False,test_baud=1000000,retry_and_timeout_counters_scaled=True),indent=2));print([s for s in log.splitlines() if 'PASS:' in s])
