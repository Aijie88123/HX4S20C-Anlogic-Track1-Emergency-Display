from pathlib import Path
import subprocess,hashlib,json
r=Path(__file__).resolve().parents[1];b=r/'B_control';sd=b/'vendor/user_source/hdl_source/SD';ip=b/'vendor/user_source/hdl_source/IP';m=Path('D:/modelsim/win64')
o=r/'evidence/dynamic_smooth_R7_20261016/animation_sdram';o.mkdir(parents=True,exist_ok=True);w=o/'work'
f=[sd/n for n in ['bmp_read.v','frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v']]
f += [b/'rtl'/n for n in ['b_media_storage.v','b_animation_cache.v','bmp_write_scaler.v','memory_startup_reset.v','ethernet_mailbox.v','remote_tf_sector.v']]
f += [ip/n for n in ['afifo_16_32_256.v','afifo_32_16_256.v']]
f += [r/'tests/tf_memory_models.v',r/'tests/tb_animation_sdram.v',Path('D:/td_extract/5E781D7/sim_release/eg4/eg_logic_bram.v')]
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f};logs=[]
def run(tool,args):
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=r/'tests',capture_output=True,timeout=1200);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-10000:])
 return s
try:
 if not w.exists():run('vlib',[str(w)])
 run('vmap',['animation_sdram_work',w.as_posix()]);run('vlog',['-sv','-work',w.as_posix(),*map(str,f)])
 observations=[]
 for profile in [1,2]:
  s=run('vsim',['-c','-l',(o/('live'+str(profile)+'.log')).as_posix(),'animation_sdram_work.tb_animation_sdram','-gPROFILE='+str(profile),'-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
  rows=[x for x in s.splitlines() if 'PASS:' in x];observations+=rows;print('\n'.join(rows),flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f}
(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':observations},indent=2))
