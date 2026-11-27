from pathlib import Path
import subprocess,json,hashlib
r=Path(__file__).resolve().parents[1];m=Path('D:/modelsim/win64');o=r/'evidence/scan_trace_20261024/native_link';o.mkdir(parents=True,exist_ok=True);w=o/'work';b=r/'B_control';sd=b/'vendor/user_source/hdl_source/SD';ip=b/'vendor/user_source/hdl_source/IP'
f=[sd/n for n in ['bmp_read.v','sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v','frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v']]
f += [b/'rtl'/n for n in ['b_media_storage.v','bmp_write_scaler.v','memory_startup_reset.v','ethernet_mailbox.v','remote_tf_sector.v']]
f += [ip/n for n in ['afifo_16_32_256.v','afifo_32_16_256.v']]
f += [r/'common/distributed_media.v',r/'A_display/rtl/a_media_cached_control.v',r/'A_display/vendor/user_source/hdl_source/SD/sd_card_bmp.v',r/'A_display/rtl/video_scanout_720p.v',r/'tests/tf_memory_models.v',r/'tests/card_spi_prev_playlist.v',r/'tests/tb_control25_chain.v',Path('D:/td_extract/5E781D7/sim_release/eg4/eg_logic_bram.v')]
f += [r/'A_display/rtl/smart_terminal_hw_top.v']
f += [r/'A_display/rtl/a_map_route_worker.v']
f += [r/'A_display/rtl/a_tf_sector_service_timed.v']
f=[r/'tests/native_link_pll.v' if p.name=='tf_memory_models.v' else r/'tests/tb_scan_native_link.v' if p.name=='tb_control25_chain.v' else p for p in f]
v=b/'vendor/user_source/hdl_source';td=Path('D:/td_extract/5E781D7/sim_release/eg4');f += [v/'include'/n for n in ['sdr_init_ref.enc.v','sdr_wrrd.enc.v','sdr_as_ram.enc.v']]+[sd/'sdram.v',td/'eg_phy_sdram_2m_32.v',r/'tests/sdram_pin_model.v']

f=[p for p in f if p.name not in ['frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v','sdram.v','sdr_init_ref.enc.v','sdr_wrrd.enc.v','sdr_as_ram.enc.v','afifo_16_32_256.v','afifo_32_16_256.v']]
f+=[r/'tests/scan_native_cfg.v']
ini=o/'modelsim.ini';ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');logs=[];all_sources=[]
def run(tool,args):
 if tool!='vlib':args=['-modelsimini',str(ini),*args]
 p=subprocess.run([str(m/(tool+'.exe')),*[str(a).replace(chr(92),'/') for a in args]],cwd=r/'tests',capture_output=True,timeout=2400)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(o/'audit.log').write_text('\n'.join(logs))
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-9000:])
 return s
if not w.exists():run('vlib',[w])
run('vmap',['work',w])
for board,lib in [('A_display','A_native'),('B_control','B_native')]:
 v=r/board/'vendor/user_source/hdl_source';libpath=o/lib
 if not libpath.exists():run('vlib',[libpath])
 run('vmap',[lib,libpath])
 files=[v/'include'/n for n in ['sdr_init_ref.enc.v','sdr_wrrd.enc.v','sdr_as_ram.enc.v']]+[v/'SD'/n for n in ['sdram.v','frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v']]+[v/'IP/afifo_16_32_256.v',v/'IP/afifo_32_16_256.v',td/'eg_logic_bram.v',td/'eg_phy_sdram_2m_32.v']
 all_sources+=files+[v/'include/global_def.v',v/'user_source/hdl_source/include/global_def.v']
 run('vlog',['-sv','+define+SIMULATION','+incdir+'+str(v/'include'),'-work',libpath,*files])
run('vlog',['-sv','-work',w,*[p for p in f if p.name!='smart_terminal_hw_top.v']])
all_sources+=f+[Path(__file__).resolve()]
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in all_sources}
s=run('vsim',['-c','-L','A_native','-L','B_native','-l',o/'live.log','work.scan_native_cfg','-do','onerror {quit -code 1}; run -all; quit -code 0'])
assert 'PASS:' in s
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in all_sources}
report={'status':'PASS','source_hashes':h,'observations':[l for l in s.splitlines() if 'PASS:' in l or 'Loading A_native' in l or 'Loading B_native' in l],'A_mem_mhz':125,'B_mem_mhz':125,'physical_test':False}
(o/'result.json').write_text(json.dumps(report,indent=2));print(report['observations'],flush=True)
