from pathlib import Path
import subprocess,hashlib,json
import numpy as np
from PIL import Image
from mesh3d_reference import render
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/3d_ui_smooth_20261018/live';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';INI=O/'modelsim.ini';INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
files=[R/'common'/n for n in ['mesh3d_divider.v','mesh3d_transport.v','ethernet_mailbox.v','distributed_map.v']]+[R/'A_display/rtl/a_mesh3d_projector.v',R/'B_control/rtl/b_mesh3d_tile_renderer.v',T/'tb_mesh3d_live.v']
sources=files+[Path(__file__).resolve(),T/'mesh3d_reference.py']+[R/'assets/map_ui'/n for n in ['atlas.hex','status.hex','compass.hex']];h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources};logs=[]
def run(tool,args):
 if tool in ['vmap','vlog','vsim']:args=['-modelsimini',INI.as_posix(),*map(str,args)]
 p=subprocess.run([str(M/(tool+'.exe')),*map(str,args)],cwd=T,capture_output=True,timeout=1200)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6000:])
 return s
try:
 if not W.exists():run('vlib',[W])
 run('vmap',['mesh_live',W]);run('vlog',['-sv','-work',W,*files])
 s=run('vsim',['-c','mesh_live.tb_mesh3d_live','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
 words=np.loadtxt(T/'mesh3d_live_words.hex',dtype=np.uint32,converters={0:lambda s:int(s,16)}).reshape(60,360,320)
 packets=[int(x,16) for x in (T/'mesh3d_live_packets.hex').read_text().splitlines()]
 meta=np.loadtxt(T/'mesh3d_live_meta.txt',dtype=np.int64)
 byframe={}
 for p in packets:byframe.setdefault((p>>16)&65535,[]).append(p)
 P=R/'assets/true3d_preview';P.mkdir(exist_ok=True);images=[];count=0
 for i,(fid,phase,pu,pv,fu,fv,yaw) in enumerate(meta):
  scene=byframe[int(fid)];assert len(scene)==118
  actual=np.repeat((words[i]&65535).astype(np.uint16),2,axis=1);expected=render(scene,int(phase))
  assert np.array_equal(actual,expected),f'RTL/reference pixels differ frame={i}'
  rgb=np.stack((((actual>>11)&31)*255//31,((actual>>5)&63)*255//63,(actual&31)*255//31),axis=-1).astype(np.uint8)
  images.append(Image.fromarray(rgb));count+=actual.size
  if i in [0,30,59]:images[-1].save(P/f'live_{i:02d}.png')
 assert len(set(meta[:,6]))>=30,'camera did not orbit'
 assert len(set(zip(meta[:,2],meta[:,3])))>=30,'person did not move'
 assert len(set(zip(meta[:,4],meta[:,5])))>=30,'camera did not follow'
 assert any(not np.array_equal(words[0],x) for x in words[1:]),'frozen output'
 images[0].save(P/'true3d_live_rtl.gif',save_all=True,append_images=images[1:],duration=33,loop=0,optimize=False)
 observations=[x for x in s.splitlines() if 'PASS:' in x]
 observations.append(f'PASS: {count} output pixels exactly equal independent depth/coverage reference over sixty continuously moving RTL frames; preview cadence 33ms is simulated, not measured on boards')
 assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
 (O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'display_pixels_checked':count,'frames':60,'observations':observations,'preview':'assets/true3d_preview/true3d_live_rtl.gif'},indent=2))
 print('\n'.join(observations),flush=True)
finally:(O/'audit.log').write_text('\n'.join(logs))
