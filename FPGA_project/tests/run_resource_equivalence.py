from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/map_detail_20261020/equivalence';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
files=[R/'common/ethernet_frame_tx.v',R/'common/ethernet_frame_rx.v',R/'common/distributed_map.v',R/'B_control/rtl/emergency_map_top.v']+[T/'reference_resource'/n for n in ['ethernet_frame_tx.v','ethernet_frame_rx.v','emergency_map_top.v']]+[T/'tb_resource_equivalence.v']
sources=files+[T/'map_partition_scenes.txt',Path(__file__).resolve()];h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=T,capture_output=True,timeout=600)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs))
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-7000:])
 return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files]);rows=[]
for top in ['tb_resource_mac_equivalence','tb_resource_map_equivalence']:
 s=run('vsim',['-modelsimini',I,'-c','-lib',W,top,'-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
 obs=[v for v in s.splitlines() if 'PASS:' in v];rows+=obs;print('\n'.join(obs),flush=True)
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
(O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':rows},indent=2))
