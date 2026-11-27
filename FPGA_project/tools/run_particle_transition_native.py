from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parents[1];O=R/'evidence/particle_transition_20261031/native_memory';O.mkdir(parents=True,exist_ok=True)
probe=R/'evidence/particle_transition_20261031/simulation/particle_transition_probe.v'
# Step8 shortens only this expensive memory regression. The production
# step2/all17 phases are independently exercised by the continuous test.
q=O/'particle_transition_probe.v';q.write_text(probe.read_text().replace('.PHASE_STEP(FAST_DEMO?2:1)', '.PHASE_STEP(8)'),encoding='utf-8')
s=(R/'tests/tb_particle_transition.v').read_text()
native=(R/'tests/tb_photo_geometry_native.v').read_text()
head=native[native.index(' reg mem='):native.index(' wire hs,vs,de,ready,rawde,frame_start;')]
head=head.replace('.geometry_mode(!rst)', '.geometry_mode(!rst)').replace('.read_req(req&&!rawvs)', '.read_req(req)').replace(".read_len(21'd512)",'.read_len(length)').replace('.read_en(word_read)','.read_en(en)')
head=head.replace('address<1843200?packed_word(address+n):32\'h98124500+n','packed_word(address+n)')
head=head.replace('write_frame(460800,230400);write_frame(691200,230400);preloaded=1;', 'write_frame(460800,230400);write_frame(691200,230400);write_frame(1843200,115200);write_frame(1958400,115200);preloaded=1;')
head=head.replace(' task write_frame;', ' task write_frame;')
head=head.replace(' frames(.geometry_mode',' memory_frames(.geometry_mode')
a=s.index(' reg [31:0] word_data=');b=s.index(' particle_transition_probe d(',a)
s=s[:a]+''' wire [31:0] word_data;wire word_empty;assign empty=word_empty;
'''+head+s[b:]
a=s.index(' always @(posedge clk)begin\n  cycles<=');b=s.index(' integer x=0,y=0',a)
s=s[:a]+''' always @(posedge clk)if(!rst && d.freeze_dynamic_frame && complete_ack)$fatal(1,"native complete ACK while frozen");
 // Concurrent real writes are confined to the staging dynamic buffer.
 initial begin wait(preloaded);forever begin repeat(20000)@(negedge net);write_frame(staging?1958400:1843200,512);end end
'''+s[b:]
a=s.index(' integer mark;');b=s.index(' initial begin #2000000000;',a)
s=s[:a]+''' initial begin
  wait(preloaded);repeat(10)@(negedge clk);rst=0;checking=1;wait(frames>=3);
  enter_particle;
  fork begin send_complete;end begin wait(!d.photo_geometry_active);end join
  wait(dynamic_frames>=2);leave_particle;wait(!d.photo_geometry_active);wait(normal_frames>=5);
  if(flip_frames!=10)$fatal(1,"native flip count %0d",flip_frames);
  @(posedge d.raw_vs);@(negedge clk);sw=2;
  repeat(2)@(posedge d.raw_vs);enter_particle;wait(!d.photo_geometry_active);wait(dynamic_frames>=4);
  leave_particle;wait(!d.photo_geometry_active);wait(normal_frames>=7);
  if(zoom_frames!=10 || writes<5 || refreshes==0)$fatal(1,"native zoom/write/refresh count %0d %0d %0d",zoom_frames,writes,refreshes);
  checking=0;
  $display("PASS: encrypted production SDRAM/FIFO, refresh and concurrent staging writes; flip/zoom both particle directions through five selected phases each, %0d complete frames/%0d exact RGB checks, %0d write jobs, %0d refresh commands, no source-area overwrite",frames,checks,writes,refreshes);$finish;
 end
'''+s[b:]
bench=O/'tb_particle_transition.v';bench.write_text(s,encoding='utf-8')
V=R/'A_display/vendor/user_source/hdl_source';S=Path('D:/td_extract/5E781D7/sim_release/eg4')
files=[V/'include'/n for n in ['sdr_init_ref.enc.v','sdr_wrrd.enc.v','sdr_as_ram.enc.v']]+[V/'SD'/n for n in ['sdram.v','frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v']]
files += [V/'IP/afifo_16_32_256.v',V/'IP/afifo_32_16_256.v',S/'eg_logic_bram.v',S/'eg_phy_sdram_2m_32.v',R/'tests/sdram_pin_model.v']
files += [R/'A_display/rtl'/n for n in ['video_scanout_720p.v','distributed_media.v','dynamic_rgb444.v','map_received_scanout.v']]+[q,bench]
bound=files+[probe,R/'A_display/rtl/smart_terminal_hw_top.v',R/'tests/tb_particle_transition.v',R/'tests/tb_photo_geometry_native.v',V/'include/global_def.v',V/'user_source/hdl_source/include/global_def.v',Path(__file__).resolve()]
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper();hashes={str(p):h(p) for p in bound}
M=Path('D:/modelsim/win64');I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');W=O/'work';logs=[]
def run(t,a):
 p=subprocess.run([str(M/(t+'.exe')),*[str(v).replace(chr(92),'/') for v in a]],cwd=O,capture_output=True,timeout=2400)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-7500:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['-modelsimini',I,'particle_native',W]);run('vlog',['-modelsimini',I,'-sv','+define+SIMULATION','+incdir+'+(V/'include').as_posix(),'-work',W,*files])
s=run('vsim',['-modelsimini',I,'-c','-l',O/'live.log','particle_native.tb_particle_transition','-do','onerror {quit -code 1}; run -all; quit -code 0'])
assert 'PASS:' in s;assert hashes=={str(p):h(p) for p in bound}
obs=[v for v in s.splitlines() if 'PASS:' in v]
(O/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=hashes,observations=obs,scope='Production encrypted SDRAM controller and real frame FIFO read/write/geometry guard with pin-level digital memory model. Verbatim top wiring; test-only phase step8 gives five full720p phases per effect/direction. Dynamic pixels12bit/static24bit, held buffers, resume and staging writes concurrent with refresh. Not board electrical/timing/HDMI measurement.'),indent=2),encoding='utf-8');print('\n'.join(obs),flush=True)
