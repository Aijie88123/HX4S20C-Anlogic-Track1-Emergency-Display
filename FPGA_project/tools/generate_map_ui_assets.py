from pathlib import Path
import json,math,sys
import numpy as np
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[1];P=R/'assets/map_ui';P.mkdir(parents=True,exist_ok=True)
ch=Path('C:/Windows/Fonts/msyhbd.ttc');mono=Path('C:/Windows/Fonts/consola.ttf')
font=lambda n:ImageFont.truetype(str(ch),n)
def panel(w,h):
 im=Image.new('L',(w,h));d=ImageDraw.Draw(im);d.rounded_rectangle((0,0,w-1,h-1),radius=3,fill=1,outline=2);return im
def text(im,xy,s,n=10):
 mask=Image.new('L',im.size);ImageDraw.Draw(mask).text(xy,s,font=font(n),fill=255,stroke_width=0)
 a=np.asarray(im).copy();a[np.asarray(mask)>=100]=3;return Image.fromarray(a)
header=panel(192,28);d=ImageDraw.Draw(header);d.line((4,5,4,22),fill=2,width=2)
header=text(header,(12,1),'动态疏散地图',14);header=text(header,(104,4),'3D / LIVE',9)
header=text(header,(12,18),'人员定位 · 危险区域 · 路线引导',8)
legend=panel(96,40)
for i,s in enumerate(['安全路线','通行道路','危险区域','人员位置']):
 d=ImageDraw.Draw(legend);yy=i*10+5
 if i<2:d.line((5,yy,17,yy),fill=2,width=2)
 elif i==2:d.polygon([(11,yy-3),(6,yy+3),(16,yy+3)],outline=2)
 else:d.ellipse((9,yy-3,13,yy+1),fill=2);d.line((11,yy,11,yy+4),fill=2)
 legend=text(legend,(23,i*10-1),s,9)
tags=[text(panel(64,12),(5,-1),s,10) for s in ['人员位置','危险区域','安全路线','路线受阻']]
atlas=np.zeros(16384,np.uint8)
def store(im,base,stride):
 a=np.asarray(im)
 for y,row in enumerate(a):atlas[base+y*stride:base+y*stride+len(row)]=row
store(header,0,256);store(legend,8192,128)
for i,im in enumerate(tags):store(im,13312+i*768,64)
status=np.zeros(16384,np.uint8)
glyphs=json.loads((P/'font5x7.json').read_text())
for mode in range(4):
 for z in range(4):
  im=Image.new('L',(128,8))
  for j,c in enumerate(f'VIEW {"ALCR"[mode]}  Z{["1.00","1.25","1.50","1.00"][z]}'):
   for yy,row in enumerate(glyphs.get(c,'00000 '*7).split()):
    for xx,v in enumerate(row):
     if v=='1':im.putpixel((2+j*6+xx,yy),255)
  status[((mode<<2)|z)*1024:(((mode<<2)|z)+1)*1024]=(np.asarray(im)>=100).ravel()
compass=np.zeros(8192,np.uint8)
for i in range(8):
 im=panel(32,32);d=ImageDraw.Draw(im);d.ellipse((4,4,27,27),outline=2)
 yaw=math.radians(-60+(i*8+3.5)*30/63)
 dx=math.sin(yaw);dy=math.cos(yaw)*210/256;length=math.hypot(dx,dy);dx/=length;dy/=length
 tip=(16+dx*11,16+dy*11);tail=(16-dx*5,16-dy*5);left=(16-dy*3,16+dx*3);right=(16+dy*3,16-dx*3)
 d.polygon([tip,left,tail,right],fill=2);d.ellipse((14,14,18,18),fill=3)
 # N marks true projected north, not a fixed screen-up direction.
 nx=round(16+dx*7)-2;ny=round(16+dy*7)-3;d.text((nx,ny),'N',font=ImageFont.truetype(str(mono),7),fill=3)
 compass[i*1024:(i+1)*1024]=np.asarray(im).ravel()
arrays={'atlas':atlas,'status':status,'compass':compass}
for name,a in arrays.items():(P/(name+'.hex')).write_text(''.join(f'{int(v):x}\n' for v in a))
(P/'layout.json').write_text(json.dumps({'atlas':{'header':[0,256,192,28],'legend':[8192,128,96,40],'person':[13312,64,64,12],'hazard':[14080,64,64,12],'route':[14848,64,64,12]},'colors':{'0':'transparent','1':'half RGB565 dark glass','2':'region accent','3':'white'},'status_variants':16,'compass_variants':8},indent=2))
tpl=(R/'tools/b_mesh3d_ui_template.v').read_text()
for name,a in arrays.items():
 bits=1 if name=='status' else 2
 init='\n'.join(f"  {name}[{i}]={bits}'d{int(v)};" for i,v in enumerate(a))
 tpl=tpl.replace(name.upper()+'_INITIAL',init)
source=(R/'tools/b_mesh3d_tile_renderer_template.v').read_text()+'\n'+tpl
target=R/'B_control/rtl/b_mesh3d_tile_renderer.v'
if '--check' in sys.argv:assert target.read_text()==source
else:target.write_text(source)
for name,im in [('header',header),('legend',legend),*[(f'tag{i}',v) for i,v in enumerate(tags)]]:
 palette=np.array([[0,0,0],[5,17,30],[0,175,235],[224,245,255]],np.uint8);Image.fromarray(palette[np.asarray(im)]).resize((im.width*4,im.height*4),Image.Resampling.NEAREST).save(P/(name+'.png'))
print('Generated B UI atlas/status/rotating compass ROMs, no full-frame or TF bitmap')
