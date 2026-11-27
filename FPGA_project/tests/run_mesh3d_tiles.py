from pathlib import Path
import subprocess,json,hashlib,numpy as np
from PIL import Image
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/3d_ui_smooth_20261018/tiles';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';INI=O/'modelsim.ini';INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
files=[R/'common/mesh3d_divider.v',R/'B_control/rtl/b_mesh3d_tile_renderer.v',T/'tb_mesh3d_tiles.v'];logs=[]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=T,capture_output=True,timeout=600)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6000:])
 return s
from mesh3d_reference import render
try:
 if not W.exists():run('vlib',[W])
 run('vmap',['-modelsimini',INI,'mesh_tiles',W]);run('vlog',['-modelsimini',INI,'-sv','-work',W,*files])
 s=run('vsim',['-modelsimini',INI,'-c','mesh_tiles.tb_mesh3d_tiles','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
 words=np.loadtxt(T/'mesh3d_tiles_rtl.hex',dtype=np.uint32,converters={0:lambda s:int(s,16)}).reshape(3,360,320)
 actual=np.repeat((words&65535).astype(np.uint16),2,axis=2)
 packets=[int(x,16) for x in (T/'mesh3d_projected.hex').read_text().splitlines()]
 expected=np.stack([render(packets[i*118:(i+1)*118],i*32) for i in range(3)])
 bad=np.argwhere(actual!=expected);assert not len(bad),[(tuple(p),hex(int(actual[tuple(p)])),hex(int(expected[tuple(p)]))) for p in bad[:16]]
 P=R/'assets/true3d_preview';P.mkdir(exist_ok=True)
 for i,a in enumerate(actual):
  rgb=np.stack((((a>>11)&31)*255//31,((a>>5)&63)*255//63,(a&31)*255//31),axis=-1).astype(np.uint8)
  Image.fromarray(rgb).save(P/f'rtl_scene_{i}.png')
 observations=[l for l in s.splitlines() if 'PASS:' in l or 'MEASURE:' in l]
 print('\n'.join(observations));print('PASS: 691200 complete-frame RGB565 pixels match independent coverage, reciprocal depth, shading and HUD model')
 (O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files+[Path(__file__).resolve(),T/'mesh3d_reference.py',T/'mesh3d_projected.hex',*[R/'assets/map_ui'/n for n in ['atlas.hex','status.hex','compass.hex']]]},'observations':observations,'display_pixels_checked':691200},indent=2))
finally:(O/'audit.log').write_text('\n'.join(logs))
