from pathlib import Path
import subprocess,json,hashlib,numpy as np
from PIL import Image
from blue_particle_model import render,channels
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/blue_ribbons_20261018/smooth_preview'
O.mkdir(parents=True,exist_ok=True);W=O/'work';INI=O/'modelsim.ini';M=Path('D:/modelsim/win64')
INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
with (T/'blue_smooth_reference.hex').open('w') as f:
 for t in range(0,512,2):f.write(''.join(f'{p:04x}\n' for p in render(t).flat))
files=[R/'B_control/rtl/b_particle_shader.v',T/'tb_blue_smooth_preview.v'];logs=[]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=T,capture_output=True,timeout=600)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6000:])
 return s
try:
 if not W.exists():run('vlib',[W])
 run('vmap',['-modelsimini',INI,'blue_preview_work',W])
 run('vlog',['-modelsimini',INI,'-sv','-work',W,*files])
 s=run('vsim',['-modelsimini',INI,'-c','blue_preview_work.tb_blue_smooth_preview','-do','onerror {quit -code 1}; run -all; quit -code 0'])
 assert 'PASS:' in s
 actual=np.loadtxt(T/'blue_smooth_rtl.hex',dtype=np.uint16,converters={0:lambda s:int(s,16)}).reshape(256,180,320)
 images=[]
 for a in actual:
  c=channels(a);rgb=np.stack((c[:,:,0]*255//31,c[:,:,1]*255//63,c[:,:,2]*255//31),axis=-1).astype(np.uint8)
  images.append(Image.fromarray(rgb).resize((640,360),Image.Resampling.NEAREST))
 P=R/'assets/realtime_particle_preview';durations=[40 if i%3==2 else 30 for i in range(256)]
 images[0].save(P/'realtime_particles_rtl.gif',save_all=True,append_images=images[1:],duration=durations,loop=0,optimize=False)
 observations=[line for line in s.splitlines() if 'PASS:' in line]
 sources=files+[Path(__file__).resolve(),T/'blue_particle_model.py',T/'blue_smooth_reference.hex']
 (O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},'observations':observations,'preview_is_simulation':True,'hardware_fps_measured':False},indent=2))
 print('\n'.join(observations),flush=True)
finally:(O/'audit.log').write_text('\n'.join(logs))
