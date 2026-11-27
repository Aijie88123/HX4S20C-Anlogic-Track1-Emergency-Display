from pathlib import Path
import subprocess,json,hashlib,numpy as np
from mesh3d_reference import render
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/3d_ui_smooth_20261018/coordinate_range';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';INI=O/'modelsim.ini';INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
vertices=[[(1024,0,65535),(1100,0,1),(1024,179,32768)],[(-1024,0,65535),(-948,0,1),(-1024,179,32768)],
 [(-512,-512,65535),(511,-512,1),(511,511,32768)],[(-512,-512,1),(-512,511,32768),(511,511,65535)]]
packets=[]
for vv in vertices:
 p=(0x12ab<<48)|(2<<44)|(7<<41)
 for j,(x,y,z) in enumerate(vv):p|=((x&4095)|((y&4095)<<12)|(z<<24))<<(64+j*40)
 packets.append(p)
fixture=T/'mesh3d_range_packets.hex';fixture.write_text(''.join(f'{p:056x}\n' for p in packets))
f=[R/'common/mesh3d_divider.v',R/'B_control/rtl/b_mesh3d_tile_renderer.v',T/'tb_mesh3d_range.v'];sources=f+[fixture,T/'mesh3d_reference.py',Path(__file__).resolve(),*[R/'assets/map_ui'/n for n in ['atlas.hex','status.hex','compass.hex']]]
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources};logs=[]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*(['-modelsimini',INI.as_posix()] if tool!='vlib' else []),*map(str,args)],cwd=T,capture_output=True,timeout=300)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-7000:])
 return s
try:
 if not W.exists():run('vlib',[W])
 run('vmap',['rangecheck',W]);run('vlog',['-sv','-work',W,*f])
 s=run('vsim',['-c','rangecheck.tb_mesh3d_range','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
 words=np.loadtxt(T/'mesh3d_range_words.hex',dtype=np.uint32,converters={0:lambda s:int(s,16)}).reshape(4,360,320)
 actual=np.repeat((words&65535).astype(np.uint16),2,axis=2)
 expected=np.stack([render([0 if i<2 else p],0) for i,p in enumerate(packets)])
 bad=np.argwhere(actual!=expected);assert not len(bad),[(tuple(v),hex(int(actual[tuple(v)])),hex(int(expected[tuple(v)]))) for v in bad[:10]]
 assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
 observations=[l for l in s.splitlines() if 'PASS:' in l]+['PASS: 921600 complete-frame display pixels match an independent full-precision integer raster model']
 (O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':observations,'display_pixels_checked':921600},indent=2));print('\n'.join(observations),flush=True)
finally:(O/'audit.log').write_text('\n'.join(logs))
