from pathlib import Path
import json,hashlib,subprocess,binascii
from PIL import Image
R=Path(__file__).resolve().parents[1];E=R/'evidence/uart_subtitle_20261026/host';E.mkdir(parents=True,exist_ok=True)
PS='C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe';tool=R/'tools/subtitle_sender.ps1';cases=[];logs=[]
for i,text in enumerate(['紧急通知：请按绿色路线疏散 EXIT A','ABC 0123456789 !?[]+-/','实验室事故 LAB B，出口2关闭','请']):
 prefix=E/('case'+str(i));p=subprocess.run([PS,'-NoProfile','-STA','-File',str(tool),'-RenderOnly','-Text',text,'-OutputPrefix',str(prefix)],capture_output=True);logs.append((p.stdout+p.stderr).decode(errors='replace'));assert p.returncode==0,logs[-1]
 data=prefix.with_suffix('.bin').read_bytes();wire=prefix.with_suffix('.uart').read_bytes();m=json.loads(prefix.with_suffix('.json').read_text(encoding='utf-8-sig'));im=Image.open(prefix.with_suffix('.png')).convert('RGB');width=m['width'];assert len(data)==2048 and len(wire)==4290 and width%16==0 and 16<=width<=1024 and im.size==(width*2,32)
 for y in range(16):
  for x in range(1024):
   word=int.from_bytes(data[(y*64+x//16)*2:(y*64+x//16)*2+2],'little');px=(word>>(15-x%16))&1
   if x<width:
    for yy in range(2):
     for xx in range(2):assert im.getpixel((x*2+xx,y*2+yy))==((255,255,255) if px else (18,56,90))
   else:assert px==0
 payload=b''
 for n in range(130):
  f=wire[n*33:n*33+33];q=f[3:31];assert f[:3]==bytes([27,83,1]) and binascii.crc_hqx(q,65535)==int.from_bytes(f[31:],'little') and q[0:2]==bytes([18,1]) and q[24:]==bytes([49,66,85,83])
  if n==0:assert q[2]==0 and int.from_bytes(q[4:6],'little')==width
  elif n==129:assert q[2]==2 and int.from_bytes(q[4:6],'little')==128 and int.from_bytes(q[6:8],'little')==binascii.crc_hqx(data,65535)
  else:assert q[2]==1 and int.from_bytes(q[4:6],'little')==n-1;payload+=q[8:24]
 assert payload==data;cases.append(dict(text=text,width=width,bytes=len(data),frames=130,all_preview_pixels_exact=True))
for i,text in enumerate([' ', '测'*100, 'x'*257, 'a'+chr(10)+'b']):
 p=subprocess.run([PS,'-NoProfile','-STA','-File',str(tool),'-RenderOnly','-Text',text,'-OutputPrefix',str(E/('reject'+str(i)))],capture_output=True);assert p.returncode!=0;logs.append((p.stdout+p.stderr).decode(errors='replace'))
(E/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
inputs=[tool,Path(__file__),R/'启动字幕工具.cmd']+[Path('C:/Windows/Fonts/msyh.ttc')]
(E/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},cases=cases,rejected=['blank','overwidth','over256UTF16','newline'],runtime='Windows PowerShell5.1 and System.Drawing',physical_COM_test=False,GUI_click_test=False),ensure_ascii=False,indent=2));print('PASS: WindowsPS5 rasterizer, complete wire and independent CRC/bit order/preview pixels, invalid input rejection')
