from pathlib import Path
import subprocess,json,hashlib,re
R=Path(__file__).resolve().parents[1];O=R/'evidence/scan_trace_20261024/protocol_fix';O.mkdir(parents=True,exist_ok=True)
V=R/'A_display/vendor/user_source/hdl_source';S=Path('D:/td_extract/5E781D7/sim_release/eg4');M=Path('D:/modelsim/win64');I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[]
base=[V/'include'/n for n in ['sdr_init_ref.enc.v','sdr_wrrd.enc.v','sdr_as_ram.enc.v']]
base += [V/'SD'/n for n in ['sdram.v','frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v']]
base += [V/'IP/afifo_16_32_256.v',V/'IP/afifo_32_16_256.v',S/'eg_logic_bram.v',S/'eg_phy_sdram_2m_32.v',R/'tests/sdram_pin_model.v',R/'tests/tb_scan_protocol.v']
original=R/'tests/reference_scan_guard/sdr_init_ref_original.enc.v'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(original)==sha(Path('D:/HX4S20C_flip_zoom_20261024/A_display/vendor/user_source/hdl_source/include/sdr_init_ref.enc.v'))
bound=base+[original,V/'include/global_def.v',V/'user_source/hdl_source/include/global_def.v',Path(__file__).resolve()]
h={p.as_posix():sha(p) for p in bound}
def run(t,args,allow_protocol_fatal=False):
 p=subprocess.run([str(M/(t+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=R/'tests',capture_output=True,timeout=900)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 known='** Fatal:' in s and 'commands dropped or refresh collided with input App burst' in s
 if '** Error' in s or ((p.returncode or '** Fatal' in s) and not(allow_protocol_fatal and known)):raise RuntimeError(s[-8000:])
 return s
cases=[]
for name,guard,post in [('before',0,0),('after',1,1)]:
 W=O/('work_'+name);lib='scan_protocol_'+name
 if not W.exists():run('vlib',[W])
 run('vmap',['-modelsimini',I,lib,W])
 files=[original if name=='before' and p.name=='sdr_init_ref.enc.v' else p for p in base]
 run('vlog',['-modelsimini',I,'-sv','+define+SIMULATION','+incdir+'+(V/'include').as_posix(),'-work',W,*files])
 s=run('vsim',['-modelsimini',I,'-c','-l',O/(name+'.log'),lib+'.tb_scan_protocol','-gGUARD_ACTIVE='+str(guard),'-gPOST_GUARD='+str(post),'-do','onerror {quit -code 1}; run -all; quit -code 0'],allow_protocol_fatal=name=='before')
 assert 'checked_words=921600' in s and 'issued_words=921600 returned_words=921600' in s
 measured={k:int(re.search(k+r'=(\d+)',s)[1]) for k in ['tRFC_violations','steady_after_initial_cache_tRFC_violations','min_ref_gap_cycles','FIFO_overflows','steady_ref_during_app']}
 if name=='before':assert measured['steady_after_initial_cache_tRFC_violations']>0 and measured['min_ref_gap_cycles']==1 and measured['steady_ref_during_app']>0
 else:assert measured['steady_after_initial_cache_tRFC_violations']==0 and measured['steady_ref_during_app']==0 and measured['min_ref_gap_cycles']>=8
 assert measured['FIFO_overflows']==0
 rows=[v for v in s.splitlines() if any(k in v for k in ['MEASURE:','VIOLATION:','ACK_LEVEL:','PASS:'])]
 cases.append(dict(name=name,measurements=measured,observations=rows));print(name+' '+json.dumps(measured),flush=True)
assert h=={p.as_posix():sha(p) for p in bound}
(O/'result.json').write_text(json.dumps(dict(status='PASS',source_hashes=h,cases=cases,scope='Exact frozen current-best refresh wrapper vs edge-deduplicated current A wrapper; real encrypted controller and asynchronous FIFO, seeded complete photo, 921600 words each. Before defect is expected. After enables existing entry guard only after seed commit, modelling display-qualified arming; first seed/loading entry remains inherited and can still violate the all-phase timing monitor. Physical corruption/white-line causality is not simulated.'),indent=2),encoding='utf-8')
