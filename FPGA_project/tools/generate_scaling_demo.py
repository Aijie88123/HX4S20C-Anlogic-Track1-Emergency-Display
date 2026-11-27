"""Generate the three current scaling demo pages, all at least 640x480. Other TF assets are preserved."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import argparse,json,struct,hashlib
R=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path);args=parser.parse_args()
out=args.output or R/'assets/tf_card/PREV_BMP';out.mkdir(parents=True,exist_ok=True)
rows=[]
for name,w,h in [('02INFO.BMP',640,480),('03INFO.BMP',800,600),('04INFO.BMP',1280,720)]:
 im=Image.new('RGB',(w,h),(18,35,61));d=ImageDraw.Draw(im)
 colours=[(255,80,80),(255,180,40),(250,235,90),(75,220,145),(75,180,255),(150,100,240)]
 for k,c in enumerate(colours):
  x0=w*k//6;x1=w*(k+1)//6
  d.rectangle((x0,h//3,x1-1,h//2),fill=c)
 for x in range(0,w,16):d.line((x,h//2,x,h-1),fill=(70,100,135))
 for y in range(h//2,h,16):d.line((0,y,w-1,y),fill=(70,100,135))
 d.line((0,h-1,w-1,h//2),fill='white',width=2)
 d.ellipse((w//2-h//8,h//2+h//12,w//2+h//8,h//2+h//3),outline=(90,230,180),width=3)
 try:font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',max(14,w//28))
 except OSError:font=ImageFont.load_default()
 d.text((w//30,h//14),f'BMP {w} x {h}',font=font,fill='white')
 d.text((w//30,h//6),'TF SCALING DEMO',font=font,fill=(90,230,180))
 im.save(out/name,format='BMP')
 raw=(out/name).read_bytes();assert raw[:2]==b'BM'
 assert struct.unpack_from('<ii',raw,18)==(w,h)
 assert struct.unpack_from('<H',raw,28)[0]==24 and struct.unpack_from('<I',raw,30)[0]==0
 rows.append({'file':name,'width':w,'height':h,'bits':24,'compression':0,'sha256':hashlib.sha256(raw).hexdigest()})
if args.output is None:
 manifest=[]
 for p in sorted(out.glob('*')):
  if not p.is_file() or p.suffix.lower()!='.bmp':continue
  raw=p.read_bytes();w,h=struct.unpack_from('<ii',raw,18)
  manifest.append({'name':p.name,'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw),'width':w,'height':abs(h)})
 (out.parent/'media-manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(json.dumps({'status':'PASS','assets':rows}))
