from pathlib import Path
import numpy as np,json
R=Path(__file__).resolve().parents[1]
P=R/'assets/indoor_map'
a=np.load(P/'palette_indices.npy');hud=np.load(P/'hud_bits.npy');pal=np.array(json.loads((P/'scene.json').read_text())['palette'],np.uint32)
edges=[(0,1),(1,2),(3,4),(4,5),(6,7),(7,8),(0,3),(3,6),(1,4),(4,7),(2,5),(5,8),(1,9),(3,10),(5,11),(7,12)]
nodes=[(80+176*(i%3),80+176*(i//3)) for i in range(9)]+[(256,0),(0,256),(512,256),(256,512)]
def solve(e,b):
 mask=[128,1,1024,32][e]
 if b in (1,2):mask|=[32768,8192,4096,16384][e]
 if b==2:mask|=[16384,32768,8192,4096][e]
 if b==3:mask|=0xf000
 root=[6,0,2,8][e];dist=[99999]*13;prev={};dist[root]=0;seen=set()
 while True:
  n=min((i for i in range(13) if i not in seen),key=lambda i:(dist[i],i),default=None)
  if n is None or dist[n]==99999:return 0,0,mask,True,9,root
  if n>=9:break
  seen.add(n)
  for k,(x,y) in enumerate(edges):
   if mask>>k&1 or n not in (x,y):continue
   m=y if n==x else x;c=dist[n]+(176 if k<12 else 80)
   if c<dist[m]:dist[m]=c;prev[m]=(n,k)
 dest=n;route=dirs=0
 while n!=root:
  parent,k=prev[n];route|=1<<k
  if (parent<n if k<12 else parent>=9 if k<14 else parent<9):dirs|=1<<k
  n=parent
 return route,dirs,mask,False,dest,root

Y,X=np.indices((480,640))
def make_scene(e,b,zoom):
 route,dirs,closed,nopath,dest,root=solve(e,b);gu,gv=nodes[root];gx=640+gu-gv;gy=136+(gu+gv)//2;eu,ev=nodes[dest];ex=640+eu-ev;ey=150+(eu+ev)//2
 return (e<<10)|(zoom<<12)|(int(nopath)<<9)|(route<<92)|(dirs<<108)|(closed<<124)|(gx<<140)|(gy<<152)|(ex<<164)|(ey<<176)|3
def render(e,b,zoom,flow,blink,scene=None):
 if scene is None:scene=make_scene(e,b,zoom)
 route=(scene>>92)&65535;dirs=(scene>>108)&65535;closed=(scene>>124)&65535;nopath=bool((scene>>9)&1)
 x=X if zoom==0 else 80+X//2+X//4 if zoom==1 else 160+X//2
 y=Y if zoom==0 else 60+Y//2+Y//4 if zoom==1 else 120+Y//2
 step=(scene>>80)&4095
 if step:
  ox=(scene>>32)&0xffffff;oy=(scene>>56)&0xffffff
  if ox&0x800000:ox-=1<<24
  if oy&0x800000:oy-=1<<24
  x=x+(ox+640*step)//8192-320;y=y+(oy+360*step)//8192-202
 band=(Y<54)|(Y>=410)|((Y>=58)&(Y<90)&((X<210)|(X>=430)))
 source_band=(y<54)|(y>=410)|((y>=58)&(y<90)&((x<210)|(x>=430)))
 content=(x>=0)&(x<640)&(y>=0)&(y<480)&~source_band
 sx=np.where(band,X,np.where(content,x,0));sy=np.where(band,Y,np.where(content,y,100));c=a[sy,sx];out=pal[c].copy()
 u=x-320+2*(y-94);v=2*(y-94)-(x-320);road=np.isin(c,[11,12,13]);live=np.zeros(X.shape,bool);arrow=live.copy();block=live.copy()
 for k,(na,nb) in enumerate(edges):
  ua,va=nodes[na];ub,vb=nodes[nb];horizontal=va==vb
  hit=(np.abs(v-va)<=10)&(u>=min(ua,ub))&(u<=max(ua,ub)) if horizontal else (np.abs(u-ua)<=10)&(v>=min(va,vb))&(v<=max(va,vb))
  if k in [1,3,5]:hit&=u>256
  if k in [7,9,11]:hit&=v>256
  if k==12:hit&=v<80
  if k==13:hit&=u<80
  if k==14:hit&=u>432
  if k==15:hit&=v>432
  if closed>>k&1:block|=hit&(((u>>3)^(v>>3))&1).astype(bool)
  if route>>k&1 and not closed>>k&1 and not nopath:
   along=u if horizontal else v;perp=np.abs(v-va) if horizontal else np.abs(u-ua);live|=hit&(perp<=8)
   phase=((along if dirs>>k&1 else -along)-2*flow)&63
   arrow|=hit&(perp<=7)&np.isin(phase+perp,[32,33])
 u0,u1,v0,v1=[(80,230,256,406),(80,230,80,230),(256,406,80,230),(256,406,256,406)][e]
 surface=(u>=u0)&(u<=u1)&(v>=v0)&(v<=v1)
 danger=surface&(((c>=4)&(c<=8))|(c>=14))
 tint=np.where(c==8,0xee6633 if blink else 0xdd5533,np.where(c==7,0x993322 if blink else 0x882222,np.where(c==6,0x883322 if blink else 0x772222,0x662222 if blink else 0x551122)))
 out[danger]=tint[danger];out[road&live]=0x44ee88;out[road&arrow]=0xaaffcc;out[road&block]=0xdd5544
 gxfield=(scene>>140)&4095;gyfield=(scene>>152)&4095;gu=(gxfield-640+2*(gyfield-136))//2;gv=(2*(gyfield-136)-(gxfield-640))//2
 gx=320+(gu-gv)//2;gy=94+(gu+gv)//4
 guide=(((abs(x-gx)<=1)&(y>=gy-7)&(y<=gy-5))|((abs(x-gx)<=3)&(y>=gy-3)&(y<=gy+2)))&(not nopath);out[guide]=0xffdd44
 for k,hit in [(12,(u>=244)&(u<=268)&(v<24)),(15,(u>=244)&(u<=268)&(v>488)),(13,(v>=244)&(v<=268)&(u<24)),(14,(v>=244)&(v<=268)&(u>488))]:
  hit&=(u>=0)&(u<=512)&(v>=0)&(v<=512);out[hit]=0xee5544 if closed>>k&1 else 0x33ddbb
 flamea=(x>=222)&(x<=226)&(y>=204-((flow>>1)&1))&(y<=212)&((y>=207)|(x==224))
 flameb=(x>=239)&(x<=243)&(y>=206-((flow>>2)&1))&(y<=213)&((y>=209)|(x==241))
 flame=(e==0)&(flamea|flameb)&surface&~road;core=((x==224)&(y>=208))|((x==241)&(y>=209));out[flame&~core]=0xffaa33;out[flame&core]=0xffee88
 # Fixed screen-space HUD is composited last, independent of map zoom.
 out[~content&~band]=0x001122;out[band]=pal[c][band]
 exit_x=(scene>>164)&4095;exit_y=(scene>>176)&4095;exitid=(3 if exit_x>640 else 4) if exit_y>400 else (1 if exit_x>640 else 2)
 count=4-sum((closed>>k)&1 for k in range(12,16));eventcolour=[0xff8855,0xffbb66,0x88ddcc,0x88ddcc][e]
 entries=[(50,65,18+e,eventcolour),(29,445,e,eventcolour),(179,445,8 if nopath else 3+exitid,0xff8855 if nopath else 0x55ff99),(329,445,9+e,0xff9955),(479,445,13+count,0xff8855 if count==0 else 0x55ddcc)]
 for hx,hy,row,col in entries:
  blockview=out[hy:hy+16,hx:hx+128];blockview[hud[row].astype(bool)]=col
 return out,scene
