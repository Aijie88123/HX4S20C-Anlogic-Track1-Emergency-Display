from pathlib import Path
import subprocess,json,hashlib,re
from native_vga_reference import render,pack
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/map_detail_20261020/chain';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
(T/'native_vga_particle.hex').write_text(''.join(f'{v:08x}\n' for v in pack(render(0))))
files=[R/'common'/n for n in ['dynamic_rgb444.v','raster_map_transport.v','raster_map_window.v','distributed_map.v','ethernet_frame_tx.v','ethernet_frame_rx.v','ethernet_raster_burst.v','ethernet_mailbox.v']]+[R/'B_control/rtl'/n for n in ['b_map_frame_renderer_vga.v','emergency_map_top.v','b_particle_shader.v','dual_board_control_top.v']]+[R/'A_display/rtl'/n for n in ['a_map_route_worker.v','smart_terminal_hw_top.v']]+[T/'tb_native_smooth_chain.v',T/'tb_native_vga_scanout.v',T/'tb_native_vga_cancel.v']
files += [Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_bram32k.v'),Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_glbl.v')]
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files+[T/'native_vga_reference.py',T/'blue_particle_model.py',Path(__file__).resolve()]}
def run(tool,args):
 if tool=='vsim':args=list(args)+['glbl']
 p=subprocess.run([str(M/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=T,capture_output=True,timeout=360)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs))
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-7000:])
 return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files])
observations=[];frames={};map_hash=None
for burst,loss in [(0,0),(1,0),(1,1)]:
 s=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_native_smooth_chain',f'-GBURST={burst}',f'-GLOSS={loss}','-do','onerror {quit -code 1}; run -all; quit -code 0'])
 assert 'PASS:' in s
 current_map_hash=hashlib.sha256((T/'native_map_words.hex').read_bytes()).hexdigest()
 if map_hash is None:map_hash=current_map_hash
 else:assert current_map_hash==map_hash,'Map input scene must be identical in the comparison'
 observations += [v for v in s.splitlines() if 'PASS:' in v or 'FRAME:' in v]
 frames[f'{burst}_{loss}']=[{k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',l)} for l in s.splitlines() if 'FRAME:' in l]
 print('\n'.join(observations[-3:]),flush=True)
for top in ['tb_native_vga_scanout','tb_native_vga_cancel']:
 s=run('vsim',['-modelsimini',I,'-c','-lib',W,top,'-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
 observations += [v for v in s.splitlines() if 'PASS:' in v]
speedup={('particle' if i==0 else 'map'):round(frames['0_0'][i]['transfer_ns']/frames['1_0'][i]['transfer_ns'],4) for i in range(2)}
assert all(v>1.05 for v in speedup.values()),speedup
assert hashes=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files+[T/'native_vga_reference.py',T/'blue_particle_model.py',Path(__file__).resolve()]}
result={'status':'PASS','source_hashes':hashes,'observations':observations,'real_100M_MAC_transfer_speedup':speedup,'frames':frames,'identical_map_frame_sha256':map_hash,'hardware_fps_measured':False}
(O/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(speedup),flush=True)
