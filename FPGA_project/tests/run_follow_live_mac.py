"""Live A -> actual MAC -> atomic mailbox -> B renderer -> MAC -> full-frame commit."""
from pathlib import Path
import sys,re,json,hashlib,subprocess,numpy as np
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'tests'));from refine2_reference import render;from native_vga_reference import pack
E=R/'evidence/follow_view_20261025/live_mac';E.mkdir(parents=True,exist_ok=True)
s=(R/'tests/tb_native_smooth_steady.v').read_text().replace('module tb_native_smooth_steady #','module tb_follow_live #')
s=s.replace('.CLK_HZ(50000000),.FRAME_CYCLES(416667)', '.CLK_HZ(25000000),.FRAME_CYCLES(416667)')
marker=' assign scene=frozen_scene;'
insert=''' assign scene=frozen_scene;
 wire scene_delivery;wire [187:0] delivered_scene;
 ethernet_mailbox #(.WIDTH(188)) moving_scene_mailbox(.src_clk(clk),.src_rst(rst),.src_valid(scene_valid),.src_data({scene_rx[211:32],8'd3}),.src_ready(),.dst_clk(render_clk),.dst_rst(rst),.dst_valid(scene_delivery),.dst_data(delivered_scene));
 reg [187:0] frame_latched;integer source_out,meta_out;reg [1023:0] source_name;
 initial meta_out=$fopen("source_scenes.txt","w");
 always @(posedge render_clk)if(renderer.state==2&&renderer.warm==7)frame_latched<=renderer.active_scene;
'''
assert marker in s;s=s.replace(marker,insert)
s=s.replace('.scene_valid(scene_valid),.scene(scene),','.scene_valid(scene_delivery),.scene(delivered_scene),')
s='\n'.join(l for l in s.splitlines() if not l.startswith(' reg [31:0] golden'))+'\n'
old='if(MAP_TEST && renderer.state==3 && (renderer.u_renderer.flow!==((frames+1)*3) || renderer.active_scene!==frozen_scene))'
s=s.replace(old,'if(MAP_TEST && renderer.state==3 && (renderer.u_renderer.flow!==((frames+1)*3) || renderer.active_scene!==frame_latched))')
old=next(l for l in s.splitlines() if 'if(wr_data!==golden[' in l)
replacement='''   if(nw==0)begin
    $sformat(source_name,"source_%0d.hex",frames);source_out=$fopen(source_name,"w");
    $fdisplay(meta_out,"%0d %047h %0d %0d",frames,renderer.active_scene,renderer.u_renderer.flow,test_phase);
   end
   $fdisplay(source_out,"%08h",wr_data);if(nw==115199)$fclose(source_out);'''
s=s.replace(old,replacement)
s=s.replace('if(MAP_TEST)wait(renderer.have_scene && renderer.pending_scene==frozen_scene);','if(MAP_TEST)wait(renderer.have_scene);')
s=s.replace('six independent arrow-phase references','independently logged live-A scenes (Python RGB oracle after simulation)')
(E/'tb.v').write_text(s)
files=[R/'common'/n for n in ['dynamic_rgb444.v','raster_map_transport.v','raster_map_window.v','distributed_map.v','ethernet_frame_tx.v','ethernet_frame_rx.v','ethernet_raster_burst.v','ethernet_mailbox.v']]+[R/'B_control/rtl'/n for n in ['b_map_frame_renderer_vga.v','emergency_map_top.v','b_particle_shader.v','dual_board_control_top.v']]+[R/'A_display/rtl/a_map_route_worker.v',R/'A_display/rtl/smart_terminal_hw_top.v',E/'tb.v']
files += [Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_bram32k.v'),Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_glbl.v')]
M=Path('D:/modelsim/win64');W=E/'work';I=E/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[v.as_posix() if isinstance(v,Path) else str(v) for v in args]],cwd=E,capture_output=True,timeout=600);text=(p.stdout+p.stderr).decode(errors='replace');logs.append(text);(E/'simulation.log').write_text('\n'.join(logs));assert p.returncode==0 and '** Error' not in text and '** Fatal' not in text,text[-4500:];return text
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,*files]);log=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb_follow_live','glbl','-GMAP_TEST=1','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in log
rows=[];offsets=set()
for line in (E/'source_scenes.txt').read_text().splitlines():
 i,h,flow,phase=line.split();i=int(i);scene=int(h,16);flow=int(flow);phase=int(phase)
 out,_=render((scene>>10)&3,0,(scene>>12)&3,flow,bool(phase&32),scene)
 expected=pack((((out>>19)&31)<<11)|(((out>>10)&63)<<5)|((out>>3)&31))
 actual=np.array([int(v,16) for v in (E/f'source_{i}.hex').read_text().splitlines()],np.uint32)
 assert actual.shape==expected.shape and np.array_equal(actual,expected),(i,'live camera pixel/packing mismatch')
 step=(scene>>80)&4095;ox=(scene>>32)&0xffffff;oy=(scene>>56)&0xffffff;ox-=1<<24 if ox&0x800000 else 0;oy-=1<<24 if oy&0x800000 else 0
 dx=(ox+640*step)//8192-320;dy=(oy+360*step)//8192-202;offsets.add((dx,dy));rows.append(dict(frame=i,scene=h,flow=flow,camera_dx=dx,camera_dy=dy))
assert len(rows)==6 and len(offsets)>=4,(len(rows),offsets)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();inputs=files+[Path(__file__),R/'tests/refine2_reference.py',R/'tests/native_vga_reference.py',R/'tests/blue_particle_model.py',R/'tests/tb_native_smooth_steady.v',R/'assets/indoor_map/palette_indices.npy',R/'assets/indoor_map/hud_bits.npy',R/'assets/indoor_map/scene.json',E/'source_scenes.txt']
(E/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes={str(p):sha(p) for p in inputs},live_frames=6,exact_RGB_pixels=1843200,exact_RGB444_words=691200,atomic_scene_mailbox=True,distinct_camera_offsets=len(offsets),frames=rows,source_sink_and_complete_commit_assertions_retained=True,physical_test=False),indent=2));print('PASS:6liveA/MAC/mailbox/render/MAC/commit frames;',len(offsets),'camera positions;1843200independentRGBpixels')
