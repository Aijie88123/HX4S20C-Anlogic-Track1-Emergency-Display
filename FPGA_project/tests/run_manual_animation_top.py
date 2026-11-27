from pathlib import Path
import subprocess,hashlib,json
r=Path(__file__).resolve().parents[1];b=r/'B_control';sd=b/'vendor/user_source/hdl_source/SD';ip=b/'vendor/user_source/hdl_source/IP';m=Path('D:/modelsim/win64')
o=r/'evidence/manual_controls_R10_20261016/integration';o.mkdir(parents=True,exist_ok=True);w=o/'work'
f=[b/'rtl'/n for n in ['dual_board_control_top.v','key_remove_shakes.v','distributed_map.v','distributed_audio.v','audio_fft.v','b_media_storage.v','b_animation_cache.v','b_map_frame_renderer.v','emergency_map_top.v','bmp_write_scaler.v','memory_startup_reset.v','ethernet_mailbox.v','remote_tf_sector.v','distributed_media.v','raster_map_transport.v','raster_map_window.v']]
f += [r/'A_display/rtl/a_media_cached_control.v',r/'A_display/rtl/map_received_scanout.v',r/'A_display/vendor/user_source/hdl_source/SD/sd_card_bmp.v']
f += [sd/n for n in ['bmp_read.v','frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v']]
f += [ip/n for n in ['afifo_16_32_256.v','afifo_32_16_256.v']]
f += [r/'tests/tf_memory_models.v',r/'tests/animation_top_link_model.v',r/'tests/tb_manual_animation_top.v',Path('D:/td_extract/5E781D7/sim_release/eg4/eg_logic_bram.v')]
ini=o/'modelsim.ini';ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f};logs=[]
def run(tool,args):
 if tool in ['vmap','vlog','vsim']:args=['-modelsimini',ini.as_posix(),*args]
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=r/'tests',capture_output=True,timeout=1200);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-10000:])
 return s
try:
 if not w.exists():run('vlib',[str(w)])
 run('vmap',['animation_top_work',w.as_posix()]);run('vlog',['-sv','-work',w.as_posix(),*map(str,f)])
 s=run('vsim',['-c','-voptargs=+acc','-l',(o/'live.log').as_posix(),'animation_top_work.tb_manual_animation_top','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
 print('\n'.join(x for x in s.splitlines() if 'PASS:' in x),flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f}
(o/'result.json').write_text(json.dumps({'status':'PASS','packet_boundary_surrogate':True,'interframe_clock_accelerated':True,'source_hashes':h,'observations':[x for x in s.splitlines() if 'PASS:' in x]},indent=2))
