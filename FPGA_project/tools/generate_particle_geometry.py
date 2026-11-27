from pathlib import Path
import numpy as np
def build_geometry():
 y,x=np.indices((180,320));u=(x-185)/185;distance=np.full((180,320),99.)
 for i in range(18):
  curve=103-45*u*u-36*u+(i-8.5)*6.2*np.abs(u)+3*np.sin(x/65+i*.34)*np.abs(u)
  distance=np.minimum(distance,np.abs(y-curve))
 for i in range(5):
  curve=109-(21+i*2)*u*u+(12-i*3)*u
  distance=np.minimum(distance,np.abs(y-curve))
 geometry=np.where(distance<.55,2,np.where(distance<1.45,1,0))
 radius=np.sqrt((x-188)**2+((y-135)*4.7)**2);floor=np.zeros_like(x,dtype=bool)
 for r in [20,34,51,72,98,129,165,207]:floor|=(np.abs(radius-r)<1)&(y>113)
 return np.where((geometry==0)&floor,3,geometry)
if __name__=='__main__':
 root=Path(__file__).resolve().parents[1];words=np.zeros(65536,dtype=np.uint8);words[:57600]=build_geometry().ravel()
 shader=root/'B_control/rtl/b_particle_shader.v';source=shader.read_text()
 a=source.index(' initial begin\n')+len(' initial begin\n');b=source.index('\n end\n function [15:0] blue',a)
 generated='\n'.join(f"  geometry[{i}]=2'd{v};" for i,v in enumerate(words))
 if source[a:b]!=generated:shader.write_text(source[:a]+generated+source[b:]);print('Geometry changed; rebuild B.')
 else:print('Geometry matches; no source changed.')
