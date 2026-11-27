import numpy as np
from blue_particle_model import geometry,palette
Y,X=np.indices((480,640));GX=X//2;GY=Y*3//8
G=geometry[GY,GX];D=abs(GX-188);DY=abs(GY-105)
def render(t):
 travel=(D+(-t if t&256 else t)+Y)%32
 lev=np.where(G==1,np.where(travel<3,6,2),0)
 core=np.where(travel<2,11,np.where(travel<4,8,np.where(travel<10,5,3)))
 core=np.where((((X&7)^(Y&7))==0)&(travel<10),13,core)
 lev=np.where(G==2,core,lev)
 f=((X>>2)+(t>>2)+(Y>>2))%32
 lev=np.where(G==3,np.where(f<4,9,np.where(f<9,5,3)),lev)
 radius=D*D+4*DY*DY;bloom=np.zeros_like(X)
 for limit,level in [(900,1),(625,2),(400,3),(256,5),(169,7),(100,9),(64,11),(36,13),(16,15)]:bloom=np.where(radius<limit,level,bloom)
 lev=np.maximum(lev,bloom)
 drift=(7-((t>>3)&7)) if t&64 else ((t>>3)&7)
 mx=(X+drift)%512;my=(Y+(t>>1))%256
 seed=(((mx>>4)<<3)|((my>>4)&7))^(((my>>4)<<4)|((mx>>4)&15))^0xb5;seed&=255
 fine_seed=((((mx>>3)&31)<<3)|((my>>3)&7))^(((my>>3)<<3)|((mx>>3)&7))^0x6d;fine_seed&=255
 fine=((fine_seed>>5)==3)&((mx&7)==(fine_seed&7))&((my&7)==((fine_seed>>3)&7))
 lev=np.where(fine,np.maximum(lev,6),lev)
 dot=abs(mx%16-(seed&15))+abs(my%16-((seed>>4)&15));valid=(seed>>6)!=0;large=((seed>>1)&3)==0
 for dist,v in [(3,3),(2,6),(1,10)]:lev=np.where(valid&large&(dot==dist),np.maximum(lev,v),lev)
 lev=np.where(valid&~large&(dot==1),np.maximum(lev,4),lev)
 lev=np.where(valid&(dot==0),np.where((seed&1)!=0,15,12),lev)
 return np.where(valid&(dot==0)&((seed&31)==3),0xfeaa,palette[lev]).astype(np.uint16)
def quantize(a):return (((a>>12)&15)<<8)|(((a>>7)&15)<<4)|((a>>1)&15)
def pack(a):
 a=quantize(a).astype(np.uint32).reshape(-1,8)
 return np.stack((a[:,0]|(a[:,1]<<12)|((a[:,2]&255)<<24),(a[:,2]>>8)|(a[:,3]<<4)|(a[:,4]<<16)|((a[:,5]&15)<<28),(a[:,5]>>4)|(a[:,6]<<8)|(a[:,7]<<20)),axis=1).ravel()
def rgb(a):
 q=quantize(a);return np.stack((((q>>8)&15)*17,((q>>4)&15)*17,(q&15)*17),axis=-1).astype(np.uint8)
