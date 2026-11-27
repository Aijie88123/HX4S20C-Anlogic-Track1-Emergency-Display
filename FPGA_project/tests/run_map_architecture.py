from pathlib import Path
import subprocess,json,hashlib
import numpy as np
R=Path(__file__).resolve().parents[1];T=R/'tests';A=R/'assets/map_architecture';O=R/'evidence/map_detail_20261020/architecture';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
d=json.loads((A/'scene.json').read_text());assert not d['unique_identity_text'];assert d['tile_types']<=512
(T/'architecture_palette.hex').write_text(''.join(f'{v:06x}\n' for v in d['palette_rgb888']))
def words(n):return np.loadtxt(A/n,dtype=np.uint16,converters={0:lambda x:int(x,16)})
index=words('tile_index.hex');atlas=words('tile_atlas.hex').reshape(512,16)
full=atlas[index].reshape(64,128,4,4).transpose(0,2,1,3).reshape(256,512)
assert np.array_equal(full,words('materials.hex').reshape(256,512))
files=[R/'common/distributed_map.v',R/'B_control/rtl/emergency_map_top.v',T/'reference_resource/emergency_map_top.v',T/'tb_map_architecture.v']
sources=files+[A/n for n in ['materials.hex','tile_index.hex','tile_atlas.hex','scene.json']]+[T/'architecture_palette.hex',T/'map_partition_scenes.txt',Path(__file__).resolve(),R/'tools/generate_map_architecture.py']
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[x.as_posix() if isinstance(x,Path) else str(x) for x in args]],cwd=T,capture_output=True,timeout=600)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs))
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6000:])
 return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files])
s=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_map_architecture','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
rows=[l for l in s.splitlines() if 'PASS:' in l or 'SCENE:' in l];print('\n'.join(rows),flush=True)
(O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':rows,'scenes':16,'native_resolution':[640,480],'surface_texture_stored_bits':d['stored_bits'],'unique_identity_text':[]},indent=2))
