from pathlib import Path
import numpy as np,struct,zlib
R=Path(__file__).resolve().parents[1]
p=np.loadtxt(R/'tests/visual_display_rtl.hex',dtype=np.uint32,converters={0:lambda x:int(x,16)}).reshape(720,1280)
rgb=np.stack((p>>16,(p>>8)&255,p&255),axis=-1).astype(np.uint8)
def write(path,a):
 def chunk(k,v):return struct.pack('>I',len(v))+k+v+struct.pack('>I',zlib.crc32(k+v))
 h,w,_=a.shape
 path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(b'\0'+r.tobytes() for r in a),9))+chunk(b'IEND',b''))
out=R/'assets/audio_visual';out.mkdir(parents=True,exist_ok=True)
write(out/'display_rtl.png',rgb)
panel=np.empty((384,416,3),np.uint8);panel[:]=[7,19,35]
panel[16:176,16:400]=rgb[130:290,40:424]
panel[208:368,16:400]=rgb[484:644,852:1236]
write(out/'panels_rtl.png',panel)
print('Actual RTL PCM/C4-triangle waveform and12-point spectrum:',out/'panels_rtl.png')
