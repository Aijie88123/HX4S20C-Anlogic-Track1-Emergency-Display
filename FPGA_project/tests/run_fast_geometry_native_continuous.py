from pathlib import Path
import subprocess,hashlib,json
R=Path(__file__).resolve().parents[1];O=R/'evidence/fast_carousel_20261025/native_continuous17';O.mkdir(parents=True,exist_ok=True)
s=(R/'tests/tb_fast_geometry_continuous.v').read_text(encoding='utf-8')
n=(R/'tests/tb_photo_geometry_native.v').read_text(encoding='utf-8')
head=n[n.index(' reg mem='):n.index(' wire hs,vs,de,ready,rawde,frame_start;')]
head=head.replace('.geometry_mode(!rst)', '.geometry_mode(active || qualified_guard)').replace(".read_len(21'd512)",".read_len(active?21'd512:21'd230400)")
begin=s.index(' wire req,en,ack,word_read,pixel_empty;');end=s.index(' wire hs,vs,de,ready,rawvs,rawde;')
replacement=''' wire req,en,ack,word_read,pixel_empty;wire [31:0] pixel_data,word_data;
 wire word_empty,rawvs;
 wire [20:0] base=active?geo_base:(hold?idle_slot:source_slot)*21'd230400;
 wire qualification;reg qualified_guard=0;
'''+head+''' always @(posedge clk or posedge mem_rst)if(mem_rst)qualified_guard<=0;else if(qualification)qualified_guard<=1;
'''
s=s[:begin]+replacement+s[end:]
s=s.replace('wire hs,vs,de,ready,rawvs,rawde;', 'wire hs,vs,de,ready,rawde;')
s=s.replace('wire sclk,ras,cas,we;', 'wire sclk,ras,cas,we;')
s=s.replace(' wire hs,vs,de,ready,rawde;', ''' wire hs,vs,de,ready,rawde;
 startup_display_qualifier q(.clk(clk),.rst(rst),.image_complete(preloaded),.normal_active(1'b1),.frame_sync(vs),.pixel_de(de),.pixel_ready(ready),.hdmi_ready(1'b1),.display_ready(qualification));
 assign eligible=qualification;
''')
s=s.replace('reg eligible=0,commit_toggle=0;', 'wire eligible;reg commit_toggle=0;')
begin=s.index(' always @(posedge clk)begin\n  cycles<=');end=s.index(' integer x=0,y=0',begin);s=s[:begin]+s[end:]
s=s.replace('repeat(10)@(negedge clk);rst=0;checking=1;', 'wait(preloaded);repeat(10)@(negedge clk);rst=0;checking=1;')
s=s.replace('wait(completed_frames>=2);@(posedge rawvs);eligible=1;', 'wait(completed_frames>=2);wait(qualification);@(posedge rawvs);')
s=s.replace('selection=2;commit(4)', 'selection=2;commit(2)').replace('commit(5);commit(6)', 'commit(2);commit(3)')
s=s.replace('if(flip_frames!=17 || zoom_frames!=34)', 'if(!qualified_guard || flip_frames!=17 || zoom_frames!=34)')
s=s.replace(' wire hs,vs,de,ready,rawde;', ''' initial begin wait(preloaded);forever begin repeat(20000)@(negedge net);write_frame(1843200,512);end end
 wire hs,vs,de,ready,rawde;''')
bench=O/'tb_fast_geometry_continuous.v';bench.write_text(s,encoding='utf-8')
M=Path('D:/modelsim/win64');I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n',encoding='utf-8');W=O/'work';logs=[]
V=R/'A_display/vendor/user_source/hdl_source';S=Path('D:/td_extract/5E781D7/sim_release/eg4')
files=[V/'include'/p for p in ['sdr_init_ref.enc.v','sdr_wrrd.enc.v','sdr_as_ram.enc.v']]
files+=[V/'SD'/p for p in ['sdram.v','frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v']]
files += [V/'IP/afifo_16_32_256.v',V/'IP/afifo_32_16_256.v',S/'eg_logic_bram.v',S/'eg_phy_sdram_2m_32.v',R/'tests/sdram_pin_model.v',R/'A_display/rtl/video_scanout_720p.v',R/'A_display/rtl/distributed_media.v',R/'A_display/rtl/smart_terminal_hw_top.v',bench]
allfiles=files+[R/'tests/tb_fast_geometry_continuous.v',R/'tests/tb_photo_geometry_native.v',V/'include/global_def.v',V/'user_source/hdl_source/include/global_def.v',Path(__file__).resolve()]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();h={str(p):sha(p) for p in allfiles}
def run(t,a):
 p=subprocess.run([str(M/(t+'.exe')),*[str(v).replace(chr(92),'/') for v in a]],capture_output=True,cwd=O,timeout=1200)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6500:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['-modelsimini',I,'geometry_cont',W]);run('vlog',['-modelsimini',I,'-sv','+define+SIMULATION','+incdir+'+(V/'include').as_posix(),'-work',W,*files])
s=run('vsim',['-modelsimini',I,'-c','-l',O/'live.log','geometry_cont.tb_fast_geometry_continuous','-do','onerror {quit -code 1}; run -all; quit -code 0'])
assert 'PASS:' in s;assert h=={str(p):sha(p) for p in allfiles}
obs=[v for v in s.splitlines() if 'PASS:' in v]
(O/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=h,observations=obs,scope='Actual encrypted SDRAM/FIFO and original startup qualifier with sticky memory guard, continuous normal-to-flip-to-zoom-to-normal, two immutable source slots,17 flip/34 zoom frames and dynamic-area background writes. Functional digital model, no physical-board measurement.'),indent=2),encoding='utf-8')
print('\n'.join(obs),flush=True)
