from pathlib import Path
import subprocess,json,hashlib,sys
import numpy as np
from PIL import Image
from native_vga_reference import render,pack,rgb
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/native_vga25_20261020/chain';O.mkdir(parents=True,exist_ok=True)
P=R/'assets/native_vga_preview';P.mkdir(parents=True,exist_ok=True)
(T/'native_vga_particle.hex').write_text(''.join(f'{v:08x}\n' for v in pack(render(0))))
files=[R/'common'/n for n in ['dynamic_rgb444.v','raster_map_transport.v','raster_map_window.v','distributed_map.v','ethernet_frame_tx.v','ethernet_frame_rx.v']]+[R/'B_control/rtl'/n for n in ['b_map_frame_renderer_vga.v','emergency_map_top.v','b_particle_shader.v']]+[R/'A_display/rtl/a_map_route_worker.v',R/'A_display/rtl/smart_terminal_hw_top.v',R/'B_control/rtl/dual_board_control_top.v',T/'tb_native_vga_chain.v',T/'tb_native_vga_scanout.v',T/'tb_native_vga_cancel.v']
snapshot={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files};M=Path('D:/modelsim/win64');W=O/'work';INI=O/'modelsim.ini';INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=T,capture_output=True,timeout=300)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-7000:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['-modelsimini',INI,'native_vga',W]);run('vlog',['-modelsimini',INI,'-sv','-work',W,*files])
s=run('vsim',['-modelsimini',INI,'-c','native_vga.tb_native_vga_chain','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
scan=run('vsim',['-modelsimini',INI,'-c','native_vga.tb_native_vga_scanout','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in scan
s+='\n'+scan
cancel=run('vsim',['-modelsimini',INI,'-c','native_vga.tb_native_vga_cancel','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in cancel
s+='\n'+cancel
assert snapshot=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
for n in ['particle','map']:
 w=np.loadtxt(T/f'native_{n}_words.hex',dtype=np.uint32,converters={0:lambda v:int(v,16)}).reshape(-1,3)
 a=np.stack((w[:,0]&4095,(w[:,0]>>12)&4095,(w[:,0]>>24)|((w[:,1]&15)<<8),(w[:,1]>>4)&4095,(w[:,1]>>16)&4095,(w[:,1]>>28)|((w[:,2]&255)<<4),(w[:,2]>>8)&4095,(w[:,2]>>20)&4095),axis=1).reshape(480,640)
 im=np.stack((((a>>8)&15)*17,((a>>4)&15)*17,(a&15)*17),axis=-1).astype(np.uint8);Image.fromarray(im).save(P/f'native_{n}_rtl.png')
packets=[]
for t in range(512):
 a=render(t);q=(((a>>12)&15)<<8)|(((a>>7)&15)<<4)|((a>>1)&15);q=q.ravel();cuts=np.flatnonzero(np.r_[True,q[1:]!=q[:-1],True]);runs=int(((np.diff(cuts)+255)//256).sum());packets.append((runs+6)//7+2)
stats={'native_resolution':[640,480],'dynamic_format':'RGB444','words_per_frame':115200,'source_render_pixels_per_frame':307200,'particle_cycle_phases':512,'particle_worst_packets':max(packets),'particle_wire_Mbps_30fps':max(packets)*84*8*30/1e6,'HDMI_output':[1280,720],'hardware_fps_measured':False}
frames=[Image.fromarray(rgb(render(t))) for t in range(0,128,4)];frames[0].save(P/'native_particle_preview.gif',save_all=True,append_images=frames[1:],duration=67,loop=0)
result={'status':'PASS','source_hashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files+[T/'native_vga_reference.py',T/'blue_particle_model.py',Path(__file__).resolve()]},'observations':[v for v in s.splitlines() if 'PASS:' in v or 'FRAME:' in v],'bandwidth':stats}
(O/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result['observations']+ [stats],ensure_ascii=False),flush=True)
