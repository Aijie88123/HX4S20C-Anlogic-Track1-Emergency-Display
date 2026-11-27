from pathlib import Path
import numpy as np
def signed(v,n):return v-(1<<n) if v>>(n-1) else v
def trunc(a,b):return abs(a)//abs(b)*(-1 if (a<0)!=(b<0) else 1)
glyphs={
 '3':'11110 00001 00001 01110 00001 00001 11110','D':'11110 10001 10001 10001 10001 10001 11110',
 'V':'10001 10001 10001 10001 10001 01010 00100','I':'11111 00100 00100 00100 00100 00100 11111',
 'E':'11111 10000 10000 11110 10000 10000 11111','W':'10001 10001 10001 10101 10101 10101 01010',
 'A':'01110 10001 10001 11111 10001 10001 10001','L':'10000 10000 10000 10000 10000 10000 11111',
 'C':'01111 10000 10000 10000 10000 10000 01111','R':'11110 10001 10001 11110 10100 10010 10001',
 'Z':'11111 00001 00010 00100 01000 10000 11111','1':'00100 01100 00100 00100 00100 00100 01110',
 '2':'01110 10001 00001 00010 00100 01000 11111','5':'11111 10000 10000 11110 00001 00001 11110',
 '0':'01110 10001 10011 10101 11001 10001 01110','.':'00000 00000 00000 00000 00000 00110 00110'}
def render(packets,phase):
 z=np.zeros((180,320),np.int64);rgb=np.ones((180,320),np.uint16)
 for p in packets:
  vertices=[]
  for j in range(3):
   w=p>>(64+j*40);vertices.append((signed(w&4095,12),signed((w>>12)&4095,12),(w>>24)&65535))
  (x0,y0,z0),(x1,y1,z1),(x2,y2,z2)=vertices;mask=(p>>41)&7;fx=(p>>44)&15;color=(p>>48)&65535
  area=(x1-x0)*(y2-y0)-(y1-y0)*(x2-x0)
  if area==0 or min(z0,z1,z2)==0:continue
  if area<0:
   x1,x2=x2,x1;y1,y2=y2,y1;z1,z2=z2,z1;area=-area;mask=((mask&1)<<2)|(mask&2)|((mask>>2)&1)
  a=max(0,min(x0,x1,x2));b=min(319,max(x0,x1,x2));c=max(0,min(y0,y1,y2));d=min(179,max(y0,y1,y2))
  if a>b or c>d:continue
  yy,xx=np.mgrid[c:d+1,a:b+1]
  e0=(x1-x0)*(yy-y0)-(y1-y0)*(xx-x0);e1=(x2-x1)*(yy-y1)-(y2-y1)*(xx-x1);e2=(x0-x2)*(yy-y2)-(y0-y2)*(xx-x2)
  gx=trunc(((z1-z0)*(y2-y0)-(z2-z0)*(y1-y0))*256,area)
  gy=trunc(((x1-x0)*(z2-z0)-(x2-x0)*(z1-z0))*256,area)
  depth=(z0*256+gx*(xx-x0)+gy*(yy-y0))
  depth=np.minimum(65535,depth>>8)
  hit=(e0>=0)&(e1>=0)&(e2>=0)&(depth>0)&(depth>z[c:d+1,a:b+1])
  eps=[abs(y0-y1)+abs(x1-x0),abs(y1-y2)+abs(x2-x1),abs(y2-y0)+abs(x0-x2)]
  edge=((mask&1!=0)&(e0<eps[0]))|((mask&2!=0)&(e1<eps[1]))|((mask&4!=0)&(e2<eps[2]))
  shade=np.full(xx.shape,color,np.uint16)
  if fx==0:
   shade=np.where((yy>>5&3)==0,0x23,np.where((yy>>5&3)==1,0x44,0x65))
   shade=np.where((xx%32==0)|(yy%32==0),0xc7,shade)
  elif color in [0xd086,0x9004]:shade[:]=0xb886 if phase&16 else 0x9004
  elif fx==1:shade=np.where((xx%16>=4)&(xx%16<=9)&(yy%16>=4)&(yy%16<=8),0x230d,shade)
  elif fx==2:shade=np.where((xx%8==2)&(yy%8==3),0x1395,shade)
  elif fx==8:shade=np.where(((xx+yy+phase)&15)<3,0xbff9,shade)
  elif fx==9 and phase&32:shade[:]=0x9004
  edgecolor=(0xfb2c if phase&16 else 0xd166) if fx in [5,9] or color in [0xd086,0x9004] else 0xffe8 if fx==6 else 0x7e0 if fx==8 else 0xffff if fx==4 else 0x2d3 if fx==3 else 0x13b5
  shade=np.where(edge,edgecolor,shade)
  z[c:d+1,a:b+1]=np.where(hit,depth,z[c:d+1,a:b+1]);rgb[c:d+1,a:b+1]=np.where(hit,shade,rgb[c:d+1,a:b+1])
 rgb=overlay_ui(rgb,packets,phase)
 return np.repeat(np.repeat(rgb,2,axis=0),2,axis=1)

P=Path(__file__).resolve().parents[1]/'assets/map_ui'
ATLAS=np.array([int(x,16) for x in (P/'atlas.hex').read_text().splitlines()],np.uint8)
STATUS=np.array([int(x,16) for x in (P/'status.hex').read_text().splitlines()],np.uint8)
COMPASS=np.array([int(x,16) for x in (P/'compass.hex').read_text().splitlines()],np.uint8)
def overlay_ui(rgb,packets,phase):
 underlay=rgb.copy()
 meta=(packets[0]>>184)&8191;mode=(meta>>11)&3;zoom=(meta>>8)&3;yaw=(meta>>2)&63
 # Paint in reverse priority, using clipped source rectangles rather than the
 # renderer's address/clock implementation.
 def paint(x,y,w,h,codes,accent):
  xx=max(0,x);yy=max(0,y);xe=min(320,x+w);ye=min(180,y+h)
  if xx>=xe or yy>=ye:return
  code=codes[yy-y:ye-y,xx-x:xe-x];base=underlay[yy:ye,xx:xe]
  ink=np.asarray(accent) if np.isscalar(accent) else np.asarray(accent)[yy-y:ye-y,xx-x:xe-x]
  rgb[yy:ye,xx:xe]=np.where(code==1,((base&0xf7de)>>1)|0x23,np.where(code==2,ink,np.where(code==3,0xcfff,base)))
 for fx,base,ink in [(8,14848,0x7e0),(4,13312,0x57f),(5,14080,0xfb2c if phase&16 else 0xd166)]:
  selected=next((p for p in packets if (p>>44)&15==fx),None)
  if selected is None or fx==8 and meta&1024:continue
  j=1 if fx==8 else 2;v=selected>>(64+j*40);x=signed(v&4095,12);y=signed((v>>12)&4095,12)
  if fx==4:x-=72;y+=32
  x=3 if x<3 else 251 if x>251 else x+3;y=38 if y<56 else 152 if y>170 else y-18
  paint(x,y,64,12,ATLAS[base:base+768].reshape(12,64),ink)
 if meta&1024:paint(6,38,64,12,ATLAS[15616:16384].reshape(12,64),0xfb2c if phase&16 else 0xd166)
 paint(280,142,32,32,COMPASS[(yaw>>3)*1024:((yaw>>3)+1)*1024].reshape(32,32),0x57f)
 variant=(mode<<2)|zoom;bits=STATUS[variant*1024:(variant+1)*1024].reshape(8,128);paint(6,166,128,8,np.where(bits,3,1),0x57f)
 legend=ATLAS[8192:13312].reshape(40,128)[:,:96];ink=np.repeat(np.repeat(np.array([0x7e0,0x2d3,0xfb2c,0x7ff]),10)[:,None],96,axis=1);paint(218,5,96,40,legend,ink)
 paint(6,5,192,28,ATLAS[:8192].reshape(32,256)[:28,:192],0x57f)
 return rgb
