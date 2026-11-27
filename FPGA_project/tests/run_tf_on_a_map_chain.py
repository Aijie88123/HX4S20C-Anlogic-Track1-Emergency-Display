from pathlib import Path
import subprocess,hashlib,json
r=Path(__file__).resolve().parents[1];m=Path('D:/modelsim/win64');o=r/'evidence/TF_on_A_20261014/render_chain';o.mkdir(parents=True,exist_ok=True);w=o/'work';b=r/'B_control';a=r/'A_display';sd=b/'vendor/user_source/hdl_source/SD';ip=b/'vendor/user_source/hdl_source/IP'
f=[sd/n for n in ['bmp_read.v','sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v','frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v']]+[b/'rtl'/n for n in ['b_media_storage.v','b_map_frame_renderer.v','emergency_map_top.v','bmp_write_scaler.v','memory_startup_reset.v']]
f += [r/'common'/n for n in ['ethernet_mailbox.v','distributed_map.v','distributed_media.v','raster_map_transport.v','remote_tf_sector.v']]+[a/'rtl'/n for n in ['map_received_scanout.v','video_scanout_720p.v']]+[ip/n for n in ['afifo_16_32_256.v','afifo_32_16_256.v']]
f += [r/'tests'/n for n in ['card_spi_storage.v','raster_storage_models.v','map_shader_reference.v','tb_tf_on_a_map_chain.v']]+[Path('D:/td_extract/5E781D7/sim_release/eg4/eg_logic_bram.v')]
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f};logs=[]
def run(tool,args):
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=r/'tests',capture_output=True,timeout=600);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-5000:])
 return s
try:
 if not w.exists():run('vlib',[str(w)])
 run('vmap',['tf_on_a_map_chain_work',str(w)]);run('vlog',['-sv','-work',str(w),*map(str,f)])
 for no_card in [0,1]:
  s=run('vsim',['-c','tf_on_a_map_chain_work.tb_tf_on_a_map_chain','-gNO_CARD='+str(no_card),'-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
  print('\n'.join(x for x in s.splitlines() if 'PASS:' in x or 'MEASURE:' in x),flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f};(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':[l for l in s.splitlines() if 'MEASURE:' in l or 'PASS:' in l]},indent=2))
