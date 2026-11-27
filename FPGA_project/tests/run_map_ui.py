from pathlib import Path
import subprocess,json,hashlib
import numpy as np
from mesh3d_reference import overlay_ui
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/3d_ui_smooth_20261018/ui';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';INI=O/'modelsim.ini';INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
f=[R/'common/mesh3d_divider.v',R/'B_control/rtl/b_mesh3d_tile_renderer.v',T/'tb_map_ui.v'];sources=f+[T/'mesh3d_reference.py',Path(__file__).resolve(),*[R/'assets/map_ui'/n for n in ['atlas.hex','status.hex','compass.hex']]]
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources};logs=[]
def run(tool,args):
 if tool in ['vmap','vlog','vsim']:args=['-modelsimini',INI.as_posix(),*map(str,args)]
 p=subprocess.run([str(M/(tool+'.exe')),*map(str,args)],cwd=T,capture_output=True,timeout=600)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6000:])
 return s
try:
 if not W.exists():run('vlib',[W])
 run('vmap',['map_ui',W]);run('vlog',['-sv','-work',W,*f])
 s=run('vsim',['-c','map_ui.tb_map_ui','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
 actual=np.loadtxt(T/'map_ui_all_pixels.hex',dtype=np.uint16,converters={0:lambda s:int(s,16)}).reshape(32,180,320)
 yy,xx=np.mgrid[:180,:320];base=(((xx&31)<<11)|((yy&63)<<5)|((xx^yy)&31)).astype(np.uint16)
 positions=[[(160,44),(153,52),(159,111)],[(-15,16),(290,180),(-15,200)],[(319,170),(-20,-10),(310,80)],[(160,110)]*3]
 for i in range(32):
  meta=((i>>2&3)<<11)|((i>>4)<<10)|((i&3)<<8)|((i&7)<<5);packets=[meta<<184]
  for fx,(x,y) in zip([4,5,8],positions[i%4]):
   j=1 if fx==8 else 2;packets.append((fx<<44)|(((x&4095)|((y&4095)<<12))<<(64+j*40)))
  expected=overlay_ui(base.copy(),packets,16 if i&8 else 0)
  if not np.array_equal(actual[i],expected):
   bad=np.argwhere(actual[i]!=expected);raise AssertionError((i,[(tuple(v),hex(int(actual[i,tuple(v)[0],tuple(v)[1]])),hex(int(expected[tuple(v)]))) for v in bad[:10]]))
 observations=[x for x in s.splitlines() if 'PASS:' in x];observations.append('PASS: 1843200 UI pixels exactly match independent region/asset compositing, including every encoded camera/zoom variant and no-path state')
 assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
 (O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'pixels_checked':1843200,'observations':observations},indent=2));print('\n'.join(observations),flush=True)
finally:(O/'audit.log').write_text('\n'.join(logs))
