from pathlib import Path
import subprocess,json,hashlib,numpy as np
from PIL import Image
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/blue_ribbons_20261018/tests';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';INI=O/'modelsim.ini';INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
from blue_particle_model import render,channels
frames=[render(t) for t in range(0,512,16)]
ref=T/'realtime_reference.hex';ref.write_text(''.join(f'{v:04x}\n' for a in frames for v in a.flat))
(T/'realtime_frame0.hex').write_text(''.join(f'{v:04x}\n' for v in frames[0].flat)+'0000\n'*256)
files=[R/'B_control/rtl/b_particle_shader.v',T/'tb_realtime_shader.v']
logs=[];observations=[]
def run(tool,args,timeout=300):
 p=subprocess.run([str(M/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=T,capture_output=True,timeout=timeout)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-8000:])
 return s
try:
 if not W.exists():run('vlib',[W])
 run('vmap',['-modelsimini',INI,'realtime_work',W]);run('vlog',['-modelsimini',INI,'-sv','-work',W,*files])
 s=run('vsim',['-modelsimini',INI,'-c','realtime_work.tb_realtime_shader','-do','onerror {quit -code 1}; run -all; quit -code 0'])
 assert 'PASS:' in s;observations.extend(l for l in s.splitlines() if 'PASS:' in l)
 actual=np.loadtxt(T/'realtime_rtl.hex',dtype=np.uint16,converters={0:lambda s:int(s,16)}).reshape(32,180,320)
 assert np.array_equal(actual,np.stack(frames))
 preview=[]
 for a in actual:
  c=channels(a);im=Image.fromarray(np.stack(((c[:,:,0]*255//31),(c[:,:,1]*255//63),(c[:,:,2]*255//31)),axis=-1).astype(np.uint8)).resize((640,360),Image.Resampling.NEAREST)
  preview.append(im)
 P=R/'assets/realtime_particle_preview';P.mkdir(parents=True,exist_ok=True)
 preview[0].save(P/'realtime_particles_rtl.gif',save_all=True,append_images=preview[1:],duration=267,loop=0,optimize=False)
 preview[2].save(P/'realtime_particles_rtl.png')
 # Worst RLE payload and wire-rate bound across the full motion cycle.
 packets=[]
 for t in range(512):
  a=render(t).ravel();changes=np.flatnonzero(np.r_[True,a[1:]!=a[:-1],True]);length=np.diff(changes)
  runs=sum((length+255)//256)+1;packets.append(int((runs+6)//7)+2)
 stats={'source_pixels':[320,180],'destination_pixels':[1280,720],'worst_data_frames_per_animation_frame':max(packets),'mean_data_frames':float(np.mean(packets)),'worst_B_wire_Mbps_at_30fps':max(packets)*84*8*30/1e6,'render_time_ms_50MHz':57600/50000,'render_timer_fps_cap':30,'hardware_fps_measured':False}
 (O/'bandwidth.json').write_text(json.dumps(stats,indent=2))
 print('\n'.join(observations));print(json.dumps(stats))
finally:(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
(O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files+[Path(__file__).resolve(),T/'blue_particle_model.py',ref]},'observations':observations,'bandwidth':stats},indent=2))
