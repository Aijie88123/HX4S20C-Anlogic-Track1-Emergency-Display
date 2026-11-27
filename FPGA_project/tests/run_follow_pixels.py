from pathlib import Path
import sys,json,hashlib,subprocess,numpy as np
from PIL import Image
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'tests'));from refine2_reference import render
E=R/'evidence/follow_view_20261025/camera_pixels';E.mkdir(parents=True,exist_ok=True);T=R/'evidence/follow_view_20261025/trajectory';cases=json.loads((T/'cases.json').read_text());frames=[];lookup={};gif_indices=[]
def add(scene,e,flow,blink,meta):
 key=(scene,e,flow,blink)
 if key not in lookup:lookup[key]=len(frames);frames.append(dict(scene=scene,event=e,flow=flow,blink=blink,meta=meta))
 return lookup[key]
for tick in range(0,144,12):
 row=cases['0'][tick];gif_indices.append(add(int(row['scene'],16),0,(tick//2*3)&31,bool(tick&32),dict(kind='actual_A_demo',case=0,tick=tick)))
for e in range(4):
 for z in range(3):
  b=(e+z)%4;c=e*12+b*3+z;t=60+z*120;row=cases[str(c)][t]
  add(int(row['scene'],16),e,(t//2*3)&31,bool(t&32),dict(kind='actual_A_cross',case=c,tick=t))
base=int(cases['0'][0]['scene'],16)
for cx,cy in [(360,290),(920,290),(360,530),(920,530)]:
 step=(base>>80)&4095;s=(base&~(((1<<48)-1)<<32))|(((cx*4096-step*640)&0xffffff)<<32)|(((cy*4096-step*360)&0xffffff)<<56)
 add(s,0,0,False,dict(kind='synthetic_camera_bound',cx=cx,cy=cy))
gold=[];mask=None;hud0=None
for i,item in enumerate(frames):
 s=item['scene'];z=(s>>12)&3;out,_=render(item['event'],0,z,item['flow'],item['blink'],s);gold.append(out)
 (E/f'gold{i}.hex').write_text(''.join(f'{int(c):06x}\n' for c in out.ravel()))
Y,X=np.indices((480,640));hudmask=(Y<54)|(Y>=410)|((Y>=58)&(Y<90)&((X<210)|(X>=430)))
for i in gif_indices:
 if hud0 is None:hud0=gold[i][hudmask]
 else:assert np.array_equal(hud0,gold[i][hudmask]),'HUD moved with map'
vectors=[]
for rows in cases.values():
 for row in rows:
  vectors.append((int(row['scene'],16)<<28)|((row['dx']&16383)<<14)|(row['dy']&16383))
(E/'camera_states.hex').write_text(''.join(f'{v:054x}\n' for v in vectors))
(E/'frames.hex').write_text(''.join(f"{int(f['scene'])|(int(f['event'])<<188)|(int(f['flow'])<<190)|(int(f['blink'])<<195):049x}\n" for f in frames))
tb='''`timescale 1ns/1ps
module tb;reg clk=0;always #10 clk=~clk;reg rst=1,active=0;reg [11:0] x=0,y=0;reg [187:0] scene=0;reg [1:0] event_type=0;reg [4:0] phase=0;reg blink=0;wire [23:0] rgb;wire [7:0] alpha;
emergency_map_top #(.REMOTE_MAP(1),.RASTER_VGA(1)) dut(.clk(clk),.rst(rst),.active(active),.state(3'd2),.event_type(event_type),.remote_live(1'b1),.remote_scene(scene),.blink_on(blink),.frame_tick(1'b0),.cx(x),.cy(y),.map_rgb(rgb),.map_alpha(alpha));
reg [215:0] camera[0:29951];reg [195:0] frames[0:NFRAME-1];reg [23:0] gold[0:307199];integer i,n,pixels=0;reg [1023:0] name;
initial begin $readmemh("camera_states.hex",camera);$readmemh("frames.hex",frames);force dut.flow=phase;repeat(8)@(negedge clk);rst=0;
for(i=0;i<29952;i=i+1)begin scene=camera[i][215:28];repeat(2)@(negedge clk);if(dut.camera_dx!==camera[i][27:14]||dut.camera_dy!==camera[i][13:0])$fatal(1,"camera packet%0d offset got%0d/%0d expected%0d/%0d",i,dut.camera_dx,dut.camera_dy,$signed(camera[i][27:14]),$signed(camera[i][13:0]));end
for(i=0;i<NFRAME;i=i+1)begin
active=0;scene=frames[i][187:0];event_type=frames[i][189:188];phase=frames[i][194:190];blink=frames[i][195];repeat(8)@(negedge clk);
$sformat(name,"gold%0d.hex",i);$readmemh(name,gold);
for(n=0;n<307204;n=n+1)begin active=n<307200;x=n%640;y=n/640;@(posedge clk);#1;if(n>=4)begin if(rgb!==gold[n-4]||alpha!==255)$fatal(1,"camera frame%0d pixel%0d got%h expected%h alpha%h",i,n-4,rgb,gold[n-4],alpha);pixels=pixels+1;end @(negedge clk);end
$display("CAMERA_FRAME%0d PASS",i);end
$display("PASS:29952actualAcameraoffsets; %0d fullcameraRGBpixels; sourceedges/background/HUDfixed checked",pixels);$finish;
end endmodule
'''.replace('NFRAME',str(len(frames)))
(E/'tb.v').write_text(tb);M=Path('D:/modelsim/win64');W=E/'work';I=E/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
sdk=[Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_bram32k.v'),Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_glbl.v')]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[v.as_posix() if isinstance(v,Path) else str(v) for v in args]],cwd=E,capture_output=True,timeout=900);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(E/'simulation.log').write_text('\n'.join(logs));assert p.returncode==0 and '** Error' not in s and '** Fatal' not in s,s[-4000:];return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,R/'B_control/rtl/emergency_map_top.v',E/'tb.v',*sdk]);s=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb','glbl','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:29952' in s
images=[]
for idx in gif_indices:
 out=gold[idx];images.append(Image.fromarray(np.stack([out>>16,(out>>8)&255,out&255],2).astype('uint8')))
images[0].save(R/'assets/indoor_map/follow_camera_verified.gif',save_all=True,append_images=images[1:],duration=200,loop=0);images[-1].save(R/'assets/indoor_map/follow_camera_last.png')
(E/'selected_frames.json').write_text(json.dumps(frames,indent=2));sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
inputs=[Path(__file__),R/'B_control/rtl/emergency_map_top.v',R/'tests/refine2_reference.py',R/'assets/indoor_map/palette_indices.npy',R/'assets/indoor_map/hud_bits.npy',R/'assets/indoor_map/scene.json',T/'cases.json',E/'tb.v',E/'camera_states.hex',E/'frames.hex',E/'selected_frames.json',*sdk]
(E/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes={str(p):sha(p) for p in inputs},actual_A_packet_offsets=29952,full_frames=len(frames),exact_RGB_alpha_pixels=len(frames)*307200,gif_frames=len(gif_indices),HUD_fixed_across_camera_frames=True,native_3zoom_4event_coverage=True,synthetic_bounds=4,background_and_baked_HUD_exclusion_checked=True,physical_fps_measured=False),indent=2));print('PASS',len(frames),'camera frames',len(frames)*307200,'pixels')
