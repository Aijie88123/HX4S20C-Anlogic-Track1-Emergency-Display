from pathlib import Path
import subprocess,json,hashlib
r=Path(__file__).resolve().parents[1];m=Path('D:/modelsim/win64');o=r/'evidence/TF_on_A_20261014/image_chain';o.mkdir(parents=True,exist_ok=True);w=o/'work';b=r/'B_control';sd=b/'vendor/user_source/hdl_source/SD';ip=b/'vendor/user_source/hdl_source/IP'
f=[sd/n for n in ['bmp_read.v','sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v','frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v']]
f += [b/'rtl'/n for n in ['b_media_storage.v','bmp_write_scaler.v','memory_startup_reset.v','ethernet_mailbox.v','remote_tf_sector.v']]
f += [ip/n for n in ['afifo_16_32_256.v','afifo_32_16_256.v']]
f += [r/'common/distributed_media.v',r/'A_display/rtl/a_media_cached_control.v',r/'A_display/vendor/user_source/hdl_source/SD/sd_card_bmp.v',r/'A_display/rtl/video_scanout_720p.v',r/'tests/tf_memory_models.v',r/'tests/card_spi_storage.v',r/'tests/tb_tf_on_a_image_chain.v',Path('D:/td_extract/5E781D7/sim_release/eg4/eg_logic_bram.v')]
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f};logs=[]
def run(tool,args):
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=r/'tests',capture_output=True,timeout=900);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s)
 return s
try:
 if not w.exists():run('vlib',[str(w)])
 run('vmap',['tf_on_a_image_chain_work',str(w)])
 run('vlog',['-sv','-work',str(w),*map(str,f)])
 for missing,full,stall in [(0,0,0)]:
  s=run('vsim',['-c','-l',str(o/'live.log'),'tf_on_a_image_chain_work.tb_tf_on_a_image_chain','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s;print('\n'.join(l for l in s.splitlines() if 'PASS:' in l),flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f}
(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h},indent=2))
