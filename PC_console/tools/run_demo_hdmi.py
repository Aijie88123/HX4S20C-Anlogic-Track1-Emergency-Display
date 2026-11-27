from pathlib import Path
import subprocess,json,hashlib,binascii
import numpy as np
from PIL import Image
R=Path(__file__).resolve().parents[1];P=Path('D:/HX4S20C_temperature_single_20261031');E=R/'evidence/demo/hdmi';E.mkdir(exist_ok=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
ps='C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
proc=subprocess.run([ps,'-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',str(R/'tools/render_demo_payloads.ps1')],capture_output=True)
assert proc.returncode==0,(proc.stdout+proc.stderr).decode(errors='replace')
images=[]
for i in range(11):
    raw=(E/f'bitmap{i}.bin').read_bytes();words=np.frombuffer(raw,'<u2').reshape(16,64);a=np.zeros((16,1024),np.uint8)
    for bit in range(16):a[:,bit::16]=(words>>(15-bit))&1
    images.append(a)
    frames=(E/f'caption{i}.uart').read_bytes();assert len(frames)==4290
    for n in range(130):
        f=frames[n*33:n*33+33]
        assert f[:3]==bytes([27,83,1]) and binascii.crc_hqx(f[3:31],65535)==int.from_bytes(f[31:33],'little')
files=[P/'A_display/rtl/subtitle_display.v',P/'common/ethernet_mailbox.v',R/'tests/tb_demo_hdmi.sv']+[Path('D:/td_extract/5E781D7/sim_release/eg4')/n for n in ['eg_phy_bram32k.v','eg_phy_glbl.v']]
M=Path('D:/modelsim/win64');W=E/'work';ini=E/'modelsim.ini';ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n',encoding='ascii');logs=[]
def run(tool,args):
    p=subprocess.run([str(M/(tool+'.exe')),*[str(a).replace('\\','/') for a in args]],cwd=E,capture_output=True,timeout=300)
    s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(E/'simulation.log').write_text('\n'.join(logs),encoding='utf-8')
    assert p.returncode==0 and '** Error' not in s and '** Fatal' not in s,s[-5000:]
    return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',ini,'-sv','-work',W,*files])
log=run('vsim',['-modelsimini',ini,'-c','-lib',W,'tb_demo_hdmi','glbl','-do','onerror {quit -code 1};run -all;quit -code 0']);assert 'PASS:' in log
widths=[int(v,16) for v in (E/'widths.hex').read_text().split()]
samples=0;on=[0]*11;rendered=[np.zeros((40,1280),np.uint8) for _ in range(11)]
with (E/'pixels.txt').open() as stream:
    for line in stream:
        c,x,y,active,pixel,bar=map(int,line.split());top=580 if c>=6 else 680
        expected=int(x<widths[c]*2 and top<=y<top+32 and images[c][(y-top)//2,x//2])
        assert active==1 and bar==1 and pixel==expected,(c,x,y,pixel,expected)
        rendered[c][y-top+4,x]=pixel;on[c]+=pixel;samples+=1
assert samples==563200 and all(on) and max(widths)*2<=1280
for i,a in enumerate(rendered):
    rgb=np.zeros((40,1280,3),np.uint8);rgb[:]=[18,56,90];rgb[a!=0]=255;Image.fromarray(rgb).save(E/f'rtl_caption_{i}.png')
inputs=files+[Path(__file__),R/'tools/render_demo_payloads.ps1',R/'tools/emergency_console_core.cs',R/'evidence/demo/caption-widths.json',E/'packets.hex',E/'widths.hex']
(E/'result.json').write_text(json.dumps({'status':'PASS','physical_HDMI':False,'RTL_exact_pixel_samples':samples,'captions':11,'host_CRC_frames':1430,'VS_commits':11,'maximum_HDMI_text_width':max(widths)*2,'source_hashes':{str(p):sha(p) for p in inputs},'scope':'Production host codec payloads into unchanged current-best subtitle_display RTL, native dual-clock BRAM, VS commit and pixel scan. No PHY/UART/full HDMI electrical or monitor test.'},ensure_ascii=False,indent=2),encoding='utf-8')
print(f'PASS: {samples} exact RTL subtitle pixels,11 captions,1430 host CRC frames,11 VS commits; maximum text width {max(widths)*2}px')
