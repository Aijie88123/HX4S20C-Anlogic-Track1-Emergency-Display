from pathlib import Path
import subprocess,json,hashlib,binascii,numpy as np
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[1];E=R/'evidence/uart_subtitle_20261026/display';E.mkdir(parents=True,exist_ok=True)
fontpath=Path('C:/Windows/Fonts/simhei.ttf');font=ImageFont.truetype(str(fontpath),16)
images=[];words=[];digests=[]
for i,s in enumerate(['请按绿色路线疏散 EVAC A1','紧急通知 EXIT B2，禁止进入！']):
 im=Image.new('1',(1024,16));draw=ImageDraw.Draw(im);box=draw.textbbox((0,0),s,font=font);draw.text((0,-box[1]),s,font=font,fill=1)
 a=np.array(im,dtype=np.uint8)
 if i==1:a[:,400:]=np.fromfunction(lambda y,x:((x*3+y*7)%17)<4,(16,624),dtype=int)
 images.append(a);w=[sum(int(a[y,x+k])<<(15-k) for k in range(16)) for y in range(16) for x in range(0,1024,16)];words+=w;payload=b''.join(v.to_bytes(2,'little') for v in w);digests.append(binascii.crc_hqx(payload,65535));Image.fromarray(a*255).save(E/f'bitmap{i}.png')
(E/'words.hex').write_text(''.join(f'{v:04x}\n' for v in words));(E/'digests.hex').write_text(''.join(f'{v:04x}\n' for v in digests))
files=[R/'A_display/rtl/subtitle_display.v',R/'common/ethernet_mailbox.v',R/'tests/tb_subtitle_display.v']+[Path('D:/td_extract/5E781D7/sim_release/eg4')/n for n in ['eg_phy_bram32k.v','eg_phy_glbl.v']]
M=Path('D:/modelsim/win64');W=E/'work';I=E/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
def run(t,args):
 p=subprocess.run([str(M/(t+'.exe')),*[str(v).replace(chr(92),'/') for v in args]],cwd=E,capture_output=True,timeout=300);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(E/'audit.log').write_text('\n'.join(logs));assert p.returncode==0 and '** Error' not in s and '** Fatal' not in s,s[-5000:];return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files]);log=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_subtitle_display','glbl','-do','onerror {quit -code 1};run -all;quit -code 0']);assert 'PASS:' in log
samples=0;counts={}
for line in (E/'pixels.txt').read_text().splitlines():
 tag,x,y,active,pixel,bar,phase=map(int,line.split());enabled=tag not in [0,6];top=580 if tag in [4,5] else 680;width=1024 if tag in [4,5] else 512;rel=x+phase-1280
 expected=int(enabled and 0<=rel<width*2 and top<=y<top+32 and images[int(tag in [4,5])][(y-top)//2,rel//2])
 assert active==int(enabled) and pixel==expected and bar==int(enabled and top-4<=y<top+36),(tag,x,y,pixel,expected,phase)
 counts[tag]=counts.get(tag,0)+pixel;samples+=1
assert counts[1]>0 and counts[4]>0 and counts[5]==0
inputs=files+[Path(__file__),fontpath,E/'words.hex',E/'digests.hex']
(E/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},exact_pixel_samples=samples,pixels_by_case=counts,CRC16=digests,observations=[s for s in log.splitlines() if 'PASS:' in s],hardware_test=False),indent=2));print('PASS:',samples,'independent subtitle pixel samples',counts)
