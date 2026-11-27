import numpy as np
palette=np.array([0x0042,0x0063,0x0084,0x00a6,0x00c8,0x012b,0x01ad,0x0251,0x03ba,0x047d,0x053f,0x061f,0x2eff,0x67bf,0xa7df,0xefff])
y,x=np.indices((180,320));d=abs(x-188);dy=abs(y-105)
u=(x-185)/185;distance=np.full((180,320),99.)
for i in range(18):
 curve=103-45*u*u-36*u+(i-8.5)*6.2*np.abs(u)+3*np.sin(x/65+i*.34)*np.abs(u)
 distance=np.minimum(distance,np.abs(y-curve))
for i in range(5):
 curve=109-(21+i*2)*u*u+(12-i*3)*u;distance=np.minimum(distance,np.abs(y-curve))
geometry=np.where(distance<.55,2,np.where(distance<1.45,1,0))
radius=np.sqrt((x-188)**2+((y-135)*4.7)**2);floor=np.zeros_like(x,dtype=bool)
for r in [20,34,51,72,98,129,165,207]:floor|=(abs(radius-r)<1)&(y>113)
geometry=np.where((geometry==0)&floor,3,geometry)
def channels(a):return np.stack(((a>>11)&31,(a>>5)&63,a&31),axis=-1)
def render(t):
 travel=(d+(-t if t&256 else t)+y)%32
 lev=np.where(geometry==1,np.where(travel<3,6,2),0)
 core=np.where(travel<2,11,np.where(travel<4,8,np.where(travel<10,5,3)))
 core=np.where((((x&7)^(y&7))==0)&(travel<10),13,core)
 lev=np.where(geometry==2,core,lev)
 f=((x>>2)+(t>>2)+(y>>2))%32
 lev=np.where(geometry==3,np.where(f<4,9,np.where(f<9,5,3)),lev)
 radius=d*d+4*dy*dy
 bloom=np.zeros_like(x)
 for limit,level in [(900,1),(625,2),(400,3),(256,5),(169,7),(100,9),(64,11),(36,13),(16,15)]:bloom=np.where(radius<limit,level,bloom)
 lev=np.maximum(lev,bloom)
 drift=(7-((t>>3)&7)) if t&64 else ((t>>3)&7)
 mx=(x+drift)%512;my=(y+(t>>1))%256
 seed=(((mx>>4)<<3)|((my>>4)&7))^(((my>>4)<<4)|((mx>>4)&15))^0xb5
 seed&=255
 fine_seed=((((mx>>3)&31)<<3)|((my>>3)&7))^(((my>>3)<<3)|((mx>>3)&7))^0x6d
 fine_seed&=255
 fine=((fine_seed>>5)==3)&((mx&7)==(fine_seed&7))&((my&7)==((fine_seed>>3)&7))
 lev=np.where(fine,np.maximum(lev,6),lev)
 dot=abs(mx%16-(seed&15))+abs(my%16-((seed>>4)&15))
 valid=(seed>>6)!=0;large=((seed>>1)&3)==0
 lev=np.where(valid&large&(dot==3),np.maximum(lev,3),lev)
 lev=np.where(valid&large&(dot==2),np.maximum(lev,6),lev)
 lev=np.where(valid&large&(dot==1),np.maximum(lev,10),lev)
 lev=np.where(valid&~large&(dot==1),np.maximum(lev,4),lev)
 lev=np.where(valid&(dot==0),np.where((seed&1)!=0,15,12),lev)
 return np.where(valid&(dot==0)&((seed&31)==3),0xfeaa,palette[lev]).astype(np.uint16)
