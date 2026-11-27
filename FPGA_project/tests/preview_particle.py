from pathlib import Path
import numpy as np
from PIL import Image

R=Path(__file__).resolve().parents[1];O=R/'assets/particle_preview';O.mkdir(parents=True,exist_ok=True)
atlas=np.array([int(x,16) for x in (R/'tests/particle_reference.hex').read_text().split()],dtype=np.int32)
y,x=np.indices((360,640));rawx=x*2;rawy=y*2
code=atlas[((rawy>>3)&63)*128+((rawx>>3)&127)];phase=(code>>3)*4;glow=code&7
# Synthetic test cards, not photographs or captured board footage.
base_a=np.stack([35+x//6,30+y//8,48+(x+y)//12],axis=2)
base_b=np.stack([15+y//12,52+x//7,75+(x+y)//8],axis=2)
for base in [base_a,base_b]:
 base[(x%80<2)|(y%60<2)]=[80,115,145]
 base[(y>110)&(y<118)&(x>90)&(x<530)]=[180,205,220]
 base[(y>160)&(y<166)&(x>90)&(x<400)]=[130,160,185]
 base[(y>205)&(y<211)&(x>90)&(x<480)]=[130,160,185]
base_a=base_a.astype(np.int32);base_b=base_b.astype(np.int32)
def frame(base,fade):
 alpha=np.clip(fade+fade//2-phase,0,255)
 hot=(fade>0)&(fade<255)&(abs((fade>>3)-(code>>3))<4)&(glow!=0)
 layer=np.zeros_like(base);layer[:,:,1]=np.where(hot,glow*16+15,0);layer[:,:,2]=np.where(hot,glow*32+31,0)
 a=alpha[:,:,None];rgb=(base*(255-a)+layer*a)//255
 return Image.fromarray(rgb.astype(np.uint8))
frames=[Image.fromarray(base_a.astype(np.uint8))];durations=[500]
values=[min(255,i*32) for i in range(1,9)]+[max(0,255-i*6) for i in range(1,44)]
for i,fade in enumerate(values):
 im=frame(base_a if i<8 else base_b,fade);frames.append(im);durations.append([20,10,20][i%3])
frames.append(Image.fromarray(base_b.astype(np.uint8)));durations.append(700)
frames[0].save(O/'particle_transition_model.gif',save_all=True,append_images=frames[1:],duration=durations,loop=0,optimize=True,disposal=2)
frame(base_b,129).save(O/'particle_midpoint.png')
print(O/'particle_transition_model.gif')
