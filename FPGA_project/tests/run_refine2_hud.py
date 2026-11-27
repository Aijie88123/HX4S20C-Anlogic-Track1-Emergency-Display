"""Font-byte exactness and scene-to-HUD binding; independent of route decision RTL."""
from pathlib import Path
import numpy as np,json,hashlib,subprocess
R=Path(__file__).resolve().parents[1];E=R/'evidence/follow_view_20261025/hud';E.mkdir(parents=True,exist_ok=True)
P=R/'assets/indoor_map';bits=np.load(P/'hud_bits.npy');base=np.load(P/'palette_indices.npy');pal=np.array(json.loads((P/'scene.json').read_text())['palette'])
cases=[];vectors=[]
for event in range(4):
 for closed in range(16):
  for dest in range(4):
   for no_path in range(2):
    ex,ey=[(896,278),(384,278),(896,534),(384,534)][dest];zoom=(closed+event)%3
    scene=3|(event<<10)|(zoom<<12)|(no_path<<9)|(closed<<136)|(ex<<164)|(ey<<176)
    ec=[0xff8855,0xffbb66,0x88ddcc,0x88ddcc][event];count=4-closed.bit_count()
    entries=[(50,65,18+event,ec),(29,445,event,ec),(179,445,8 if no_path else 4+dest,0xff8855 if no_path else 0x55ff99),(329,445,9+event,0xff9955),(479,445,13+count,0xff8855 if count==0 else 0x55ddcc)]
    pixels=[]
    for x0,y0,row,col in entries:
     ones=np.argwhere(bits[row]);zeros=np.argwhere(bits[row]==0)
     for yy,xx in [*ones[:8],*zeros[::max(1,len(zeros)//8)][:8]]:
      x=x0+int(xx);y=y0+int(yy);rgb=col if bits[row,yy,xx] else int(pal[base[y,x]])
      pixels.append((x,y,rgb))
    assert len(pixels)==80
    cases.append((scene,event));vectors+=pixels
(E/'scenes.hex').write_text(''.join(f'{(e<<188)|s:048x}\n' for s,e in cases))
(E/'samples.hex').write_text(''.join(f'{(x<<36)|(y<<24)|rgb:012x}\n' for x,y,rgb in vectors))
tb='''`timescale 1ns/1ps
module tb;reg clk=0;always #10 clk=~clk;reg rst=1;reg [11:0] x=0,y=0;reg [187:0] scene=0;reg [1:0] event_type=0;
wire [23:0] rgb;wire [7:0] alpha;
emergency_map_top #(.REMOTE_MAP(1),.RASTER_VGA(1)) dut(.clk(clk),.rst(rst),.active(1'b1),.state(3'd2),.event_type(event_type),.remote_live(1'b1),.remote_scene(scene),.blink_on(1'b0),.frame_tick(1'b0),.cx(x),.cy(y),.map_rgb(rgb),.map_alpha(alpha));
reg [12:0] font_address=0;wire [7:0] font_q;reg [7:0] font_gold[0:8191];
refine2_hud_bytes_rom font(.clk(clk),.address(font_address),.q(font_q));
reg [189:0] scenes[0:511];reg [47:0] samples[0:40959];integer i,c,n,total=0;
initial begin
$readmemh("FONT_PATH",font_gold);$readmemh("scenes.hex",scenes);$readmemh("samples.hex",samples);
repeat(8)@(negedge clk);rst=0;
for(i=0;i<8192;i=i+1)begin font_address=i;@(posedge clk);#1;if(font_q!==font_gold[i])$fatal(1,"font byte%0d",i);@(negedge clk);end
for(c=0;c<512;c=c+1)begin
scene=scenes[c][187:0];event_type=scenes[c][189:188];repeat(8)@(negedge clk);
for(n=0;n<84;n=n+1)begin
if(n<80)begin x=samples[c*80+n][47:36];y=samples[c*80+n][35:24];end
@(posedge clk);#1;
if(n>=4)begin if(rgb!==samples[c*80+n-4][23:0]||alpha!==255)$fatal(1,"HUD scene=%0d sample=%0d got=%h expected=%h",c,n-4,rgb,samples[c*80+n-4][23:0]);total=total+1;end
@(negedge clk);
end end
$display("PASS:8192fontbytes65536bits;512scenecombinations40960HUDsamples;4events16exitmasks4targets2noPath;screenfixedforall3zooms");$finish;
end endmodule
'''.replace('FONT_PATH',(P/'hud.hex').as_posix())
(E/'tb.v').write_text(tb);M=Path('D:/modelsim/win64');W=E/'work';I=E/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
sdk=[Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_bram32k.v'),Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_glbl.v')]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[v.as_posix() if isinstance(v,Path) else str(v) for v in args]],cwd=E,capture_output=True,timeout=300);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(E/'simulation.log').write_text('\n'.join(logs));assert p.returncode==0 and '** Error' not in s and '** Fatal' not in s,s[-3500:];return s
if not W.exists():run('vlib',[W])
run('vlog',['-modelsimini',I,'-sv','-work',W,R/'B_control/rtl/emergency_map_top.v',E/'tb.v',*sdk])
s=run('vsim',['-modelsimini',I,'-c','-lib',W,'tb','glbl','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:8192' in s
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
(E/'result.json').write_text(json.dumps(dict(status='PASS',font_bits=65536,scene_combinations=512,HUD_samples=40960,source_hashes={str(p):sha(p) for p in [Path(__file__),R/'B_control/rtl/emergency_map_top.v',P/'hud_bits.npy',P/'hud.hex',P/'palette_indices.npy',P/'scene.json',E/'tb.v',E/'scenes.hex',E/'samples.hex',*sdk]},observations=[v for v in s.splitlines() if 'PASS:' in v]),indent=2));print(s[-500:])
