from pathlib import Path
import subprocess,json,hashlib,binascii,numpy as np
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[1];E=R/'evidence/uart_subtitle_20261026/text';E.mkdir(parents=True,exist_ok=True)
files=[R/'A_display/rtl/text_overlay_8x8.v',R/'tests/subtitle_parent_text.v',R/'tests/tb_subtitle_text.v']
files += [Path('D:/td_extract/5E781D7/sim_release/eg4')/n for n in ['eg_phy_bram32k.v','eg_phy_glbl.v']]
M=Path('D:/modelsim/win64');W=E/'work';I=E/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
def run(t,args):
 p=subprocess.run([str(M/(t+'.exe')),*[str(v).replace(chr(92),'/') for v in args]],cwd=E,capture_output=True,timeout=300);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(E/'audit.log').write_text('\n'.join(logs));assert p.returncode==0 and '** Error' not in s and '** Fatal' not in s,s[-5000:];return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files]);observations=[]
for width in [1280,640]:
 log=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_subtitle_text','glbl','-GW='+str(width),'-do','onerror {quit -code 1};run -all;quit -code 0']);assert 'PASS:' in log;observations += [s for s in log.splitlines() if 'PASS:' in s]
inputs=files+[Path(__file__)]
(E/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},observations=observations,hardware_test=False),indent=2));print(observations)
