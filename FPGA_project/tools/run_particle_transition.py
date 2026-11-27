"""Exercise the real top-level wiring, cache hold, unpacker and scanout."""
from pathlib import Path
import json,hashlib,subprocess
R=Path(__file__).resolve().parents[1];O=R/'evidence/particle_transition_20261031/simulation';O.mkdir(parents=True,exist_ok=True)
top=(R/'A_display/rtl/smart_terminal_hw_top.v').read_text(encoding='utf-8-sig')
def part(a,b):return top[top.index(a):top.index(b,top.index(a))]
early=part('    wire photo_geometry_active,',' wire map_commit_animation')
control=part('    // Flip/zoom across','    // Preserve the original first-image')
scan=part('    wire [31:0] normal_pixel_data;','    startup_display_qualifier u_startup')
cache=part('     map_received_frame_control #','    end else begin: parameter_map_reference')
function=part('    function [20:0] media_frame_base;','    generate if(ENABLE_MEDIA)')
mux=part('    assign video_read_req=','    frame_read_write #(')
resolution=part('    always @(posedge video_clk or posedge rst_all) begin\n        if (rst_all) begin\n            res_tgl_sync', '    display_parameter_control u_display_parameters')
import re
base=re.search(r'\.read_addr_0\s*\((.*?)\),',top)[1]
length=re.search(r'\.read_len\s*\((.*?)\),',top)[1]
wrapper='''`timescale 1ns/1ps
module particle_transition_probe(input video_clk,rst_all,input [3:0] sw,input [2:0] display_slot,input disp_src_toggle,
 input emergency_mode,input [1:0] emergency_event,input [1:0] normal_animation_ready_video,
 input map_cdc_valid,input [1:0] map_commit_event,input map_commit_animation,
 output map_cdc_ready,map_staging_slot,map_display_slot,map_mode,map_display_animation,map_have,
 output video_read_req,video_read_en,input video_read_req_ack,video_read_empty,input [31:0] video_read_data,
 output [20:0] read_base,read_len,output hs,vs,de,output [23:0] vout_data_raw);
 localparam ENABLE_MEDIA=1,FEATURE_MASK=15,FAST_DEMO=1,FRAME_PIXELS=307200,BUF0_ADDR=0;
 wire startup_display_ready=1,display_valid_video_2=1,sd_hard_recover=0;wire [1:0] emergency_map_ready_video=3;
 wire raw_vs,raw_hs,raw_de,raw_frame_start;wire [11:0] raw_x,raw_y;
 wire map_frame_req,map_frame_en,map_hs,map_vs,map_de;wire [23:0] map_frame_rgb;
 wire normal_frame_req,normal_frame_en,normal_hs,normal_vs,normal_de,normal_pixel_ready;wire [23:0] normal_rgb;
 reg [2:0] res_tgl_sync;reg [15:0] res_w_v,res_h_v;wire [15:0] disp_src_w=640,disp_src_h=480;
'''+early+resolution+function+control+scan+cache+mux+f' assign read_base={base};\n assign read_len={length};\nendmodule\n'
probe=O/'particle_transition_probe.v';probe.write_text(wrapper,encoding='utf-8')
M=Path('D:/modelsim/win64');I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n',encoding='utf-8');W=O/'work';logs=[]
files=[R/'A_display/rtl'/n for n in ['video_scanout_720p.v','distributed_media.v','dynamic_rgb444.v','map_received_scanout.v']]+[probe,R/'tests/tb_particle_transition.v']
bound=files+[R/'A_display/rtl/smart_terminal_hw_top.v',Path(__file__).resolve()]
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper();hashes={str(p):h(p) for p in bound}
def run(t,a):
 p=subprocess.run([str(M/(t+'.exe')),*[str(v).replace(chr(92),'/') for v in a]],cwd=O,capture_output=True,timeout=2400)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-9000:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['-modelsimini',I,'particle_transition',W]);run('vlog',['-modelsimini',I,'-sv','-work',W,*files])
s=run('vsim',['-modelsimini',I,'-c','-l',O/'live.log','particle_transition.tb_particle_transition','-do','onerror {quit -code 1}; run -all; quit -code 0'])
assert 'PASS:' in s;assert hashes=={str(p):h(p) for p in bound}
obs=[v for v in s.splitlines() if 'PASS:' in v]
(O/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=hashes,observations=obs,scope='Verbatim production top-level transition/cache/scanout wiring. Real geometry controller and both data formats; full continuous HDMI rasters through17-stage flip/zoom entry/exit, held complete-frame commits, resumed motion, queued manual input, switches and emergency cancellation. Functional FIFO model, not physical HDMI or SDRAM timing.'),indent=2),encoding='utf-8')
print('\n'.join(obs),flush=True)
