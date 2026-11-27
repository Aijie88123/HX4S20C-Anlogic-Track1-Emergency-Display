from pathlib import Path
import numpy as np,json,hashlib,subprocess,heapq,time
from PIL import Image
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/follow_view_20261025/pixels';O.mkdir(parents=True,exist_ok=True)
P=R/'assets/indoor_map';a=np.load(P/'palette_indices.npy');pal=np.array(json.loads((P/'scene.json').read_text())['palette'],np.uint32)
edges=[(0,1),(1,2),(3,4),(4,5),(6,7),(7,8),(0,3),(3,6),(1,4),(4,7),(2,5),(5,8),(1,9),(3,10),(5,11),(7,12)]
nodes=[(80+176*(i%3),80+176*(i//3)) for i in range(9)]+[(256,0),(0,256),(512,256),(256,512)]
def solve(e,b):
 mask=[128,1,1024,32][e]
 if b in (1,2):mask|=[32768,8192,4096,16384][e]
 if b==2:mask|=[16384,32768,8192,4096][e]
 if b==3:mask|=0xf000
 root=[6,0,2,8][e];dist=[99999]*13;prev={};dist[root]=0;seen=set()
 while True:
  n=min((i for i in range(13) if i not in seen),key=lambda i:(dist[i],i),default=None)
  if n is None or dist[n]==99999:return 0,0,mask,True,9,root
  if n>=9:break
  seen.add(n)
  for k,(x,y) in enumerate(edges):
   if mask>>k&1 or n not in (x,y):continue
   m=y if n==x else x;c=dist[n]+(176 if k<12 else 80)
   if c<dist[m]:dist[m]=c;prev[m]=(n,k)
 dest=n;route=dirs=0
 while n!=root:
  parent,k=prev[n];route|=1<<k
  if (parent<n if k<12 else parent>=9 if k<14 else parent<9):dirs|=1<<k
  n=parent
 return route,dirs,mask,False,dest,root
Y,X=np.indices((480,640));scenes=[];previews=[]
for e in range(4):
 for b in range(4):
  for zoom in range(3):
   n=len(scenes);flow=n%32;blink=bool(n&1);route,dirs,closed,nopath,dest,root=solve(e,b)
   gu,gv=nodes[root];gx=640+gu-gv;gy=136+(gu+gv)//2;eu,ev=nodes[dest];ex=640+eu-ev;ey=150+(eu+ev)//2
   scene=(e<<10)|(zoom<<12)|(int(nopath)<<9)|(route<<92)|(dirs<<108)|(closed<<124)|(gx<<140)|(gy<<152)|(ex<<164)|(ey<<176)|3
   scenes.append((scene,e,blink,flow))
   from refine2_reference import render
   out,scene=render(e,b,zoom,flow,blink)
   (O/f'gold{n}.hex').write_text(''.join(f'{int(z):06x}\n' for z in out.ravel()))
   if zoom==0:
    rgb=np.stack([out>>16,(out>>8)&255,out&255],2).astype('uint8');Image.fromarray(rgb).save(P/f'scene_{e}_barrier_{b}.png')
   if zoom==0 and b==0:previews.append(Image.fromarray(np.stack([out>>16,(out>>8)&255,out&255],2).astype('uint8')))
previews[0].save(P/'scenes.gif',save_all=True,append_images=previews[1:],duration=900,loop=0)
(O/'scenes.hex').write_text(''.join(f'{s:047x}\n' for s,e,b,f in scenes))
tb='''`timescale 1ns/1ps
module tb;reg clk=0;always #10 clk=~clk;reg rst=1,active=0;reg [11:0] x=0,y=0;reg [187:0] scene;
wire [23:0] rgb;wire [7:0] alpha;reg [1:0] event_type;reg blink;reg [4:0] phase;
emergency_map_top #(.REMOTE_MAP(1),.RASTER_VGA(1)) dut(.clk(clk),.rst(rst),.active(active),.state(3'd2),.event_type(event_type),.remote_live(1'b1),.remote_scene(scene),.blink_on(blink),.frame_tick(1'b0),.cx(x),.cy(y),.map_rgb(rgb),.map_alpha(alpha));
reg [23:0] gold[0:307199];reg [187:0] scenes[0:47];integer s,n,total=0;reg [1023:0] name;
initial begin $readmemh("scenes.hex",scenes);force dut.flow=phase;repeat(8)@(negedge clk);rst=0;
for(s=0;s<48;s=s+1)begin
active=0;repeat(8)@(negedge clk);scene=scenes[s];event_type=s/12;blink=s%2;phase=s%32;
$sformat(name,"gold%0d.hex",s);$readmemh(name,gold);
for(n=0;n<307204;n=n+1)begin
active=n<307200;x=n%640;y=n/640;
@(posedge clk);#1;
if(n>=4)begin if(rgb!==gold[n-4]||alpha!==255)begin $display("FAIL scene=%0d pix=%0d rgb=%h expected=%h alpha=%h",s,n-4,rgb,gold[n-4],alpha);$fatal;end total=total+1;end
@(negedge clk);
end $display("FRAME %0d PASS",s);
end
$display("PASS: %0d pixels48scenes4events4barriers3zooms fiveclock exact",total);$finish;
end
endmodule
'''
(O/'tb.v').write_text(tb);M=Path('D:/modelsim/win64');W=O/'work';I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[q.as_posix() if isinstance(q,Path) else str(q) for q in args]],cwd=O,capture_output=True,timeout=900);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'simulation.log').write_text('\n'.join(logs))
 assert p.returncode==0 and '** Error' not in s and '** Fatal' not in s,s[-4000:]
 return s
if not W.exists():run('vlib',[W])
sdk=[Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_bram32k.v'),Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_glbl.v')]
run('vlog',['-modelsimini',I,'-sv','-work',W,R/'B_control/rtl/emergency_map_top.v',O/'tb.v',*sdk])
s=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb','glbl','-do','onerror {quit -code 1}; run -all; quit -code 0'])
assert 'PASS: 14745600' in s,s[-2000:]
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
(O/'result.json').write_text(json.dumps(dict(status='PASS',pixels=14745600,scenes=48,source_hashes={str(p):h(p) for p in [R/'B_control/rtl/emergency_map_top.v',R/'tools/indoor_renderer_template.v',R/'tools/generate_indoor_map.py',P/'palette_indices.npy',P/'hud_bits.npy',R/'tests/refine2_reference.py',Path(__file__).resolve(),O/'tb.v',*sdk]},observations=[s for s in s.splitlines() if 'PASS:' in s]),indent=2))
print(s[-500:])
