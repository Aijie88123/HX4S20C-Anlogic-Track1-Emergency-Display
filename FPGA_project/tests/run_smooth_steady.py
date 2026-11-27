from pathlib import Path
import subprocess,json,hashlib
from native_vga_reference import render,pack
from indoor_motion_reference import render as indoor_render
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/map_detail_20261020/steady';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
(T/'native_steady_particles.hex').write_text(''.join(''.join(f'{v:08x}\n' for v in pack(render(t))) for t in range(0,12,2)))
(T/'native_steady_map.hex').write_text(''.join(f'{int(v):08x}\n' for phase in range(3,19,3) for v in indoor_render(phase)))
files=[R/'common'/n for n in ['dynamic_rgb444.v','raster_map_transport.v','raster_map_window.v','distributed_map.v','ethernet_frame_tx.v','ethernet_frame_rx.v','ethernet_raster_burst.v','ethernet_mailbox.v']]+[R/'B_control/rtl'/n for n in ['b_map_frame_renderer_vga.v','emergency_map_top.v','b_particle_shader.v','dual_board_control_top.v']]+[R/'A_display/rtl/a_map_route_worker.v',R/'A_display/rtl/smart_terminal_hw_top.v',T/'tb_native_smooth_steady.v']
files += [Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_bram32k.v'),Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_glbl.v')]
source=files+[T/'native_steady_particles.hex',T/'native_steady_map.hex',T/'native_vga_reference.py',T/'blue_particle_model.py',T/'indoor_motion_reference.py',T/'refine2_reference.py',R/'assets/indoor_map/hud_bits.npy',R/'assets/indoor_map/palette_indices.npy',R/'assets/indoor_map/scene.json',Path(__file__).resolve()];h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in source}
def run(tool,args):
 if tool=='vsim':args=list(args)+['glbl']
 p=subprocess.run([str(M/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=T,capture_output=True,timeout=360)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs))
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6000:])
 return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files])
rows=[]
for mode in [0,1]:
 s=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_native_smooth_steady',f'-GMAP_TEST={mode}','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
 obs=[v for v in s.splitlines() if 'PASS:' in v or 'FRAME:' in v];rows+=obs;print('\n'.join(obs),flush=True)
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in source}
(O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':rows,'simulated_steady_fps':30,'modes_checked':['six independent particle phases','six complete detailed-map frames'],'hardware_fps_measured':False,'limits':'Ideal modeled SDRAM FIFO service; simulation cadence, not a hardware FPS measurement or an all-scene sustained-FPS claim.'},indent=2))
