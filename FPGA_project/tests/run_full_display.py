from pathlib import Path
import subprocess,json,hashlib,sys
r=Path(__file__).resolve().parents[1];m=Path('D:/modelsim/win64');o=r/'evidence/TF_link_fix_20261014/full_display';o.mkdir(parents=True,exist_ok=True);w=o/'work';b=r/'B_control';sd=b/'vendor/user_source/hdl_source/SD';ip=b/'vendor/user_source/hdl_source/IP'
required_vectors=[r/'tests/storage_recovery_vectors'/('full_'+suffix)
    for suffix in ['disk.hex','expected.hex','starts.hex','sizes.hex','manifest.json']]
if not all(path.is_file() for path in required_vectors):
    subprocess.run([sys.executable,str(r/'tests/generate_storage_recovery_vectors.py')],check=True)
f=[sd/n for n in ['bmp_read.v','sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v','frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v']]
f += [b/'rtl'/n for n in ['b_media_storage.v','bmp_write_scaler.v','memory_startup_reset.v','ethernet_mailbox.v','remote_tf_sector.v']]
f += [ip/n for n in ['afifo_16_32_256.v','afifo_32_16_256.v']]
f += [r/'common/distributed_media.v',r/'A_display/rtl/a_media_cached_control.v',r/'A_display/vendor/user_source/hdl_source/SD/sd_card_bmp.v',r/'A_display/rtl/video_scanout_720p.v',r/'tests/tf_memory_models.v',r/'tests/card_spi_full_display.v',r/'tests/tb_full_display.v',Path('D:/td_extract/5E781D7/sim_release/eg4/eg_logic_bram.v')]
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f};logs=[]
fixtures=[r/'tests/storage_recovery_vectors'/n for n in ['full_disk.hex','full_starts.hex','full_expected.hex','full_manifest.json']]
fh={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in fixtures}
fixture_manifest=json.loads((r/'tests/storage_recovery_vectors/full_manifest.json').read_text())
for asset in fixture_manifest['source_assets']:
 p=r/'A_display/assets/tf_card_six'/asset['name'];assert hashlib.sha256(p.read_bytes()).hexdigest()==asset['sha256']
def run(tool,args):
 import time,threading
 p=subprocess.Popen([str(m/(tool+'.exe')),*args],cwd=r/'tests',stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',bufsize=1)
 timed_out=[]
 def kill():
  timed_out.append(True)
  subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],capture_output=True)
  if p.poll() is None:p.kill()
 timer=threading.Timer(2400,kill);timer.start();lines=[]
 try:
  with (o/'stream.log').open('a',encoding='utf-8') as live:
   for line in p.stdout:
    lines.append(line);live.write(line);live.flush()
    if 'TRACE:' in line or 'PASS:' in line:print(line.rstrip(),flush=True)
  rc=p.wait()
 finally:timer.cancel()
 s=''.join(lines);logs.append(s)
 if timed_out or rc or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-12000:])
 return s
try:
 if not w.exists():run('vlib',[str(w)])
 run('vmap',['full_display_work',str(w)])
 run('vlog',['-sv','-work',str(w),*map(str,f)])
 for missing,full,stall in [(0,0,0)]:
  s=run('vsim',['-c','-l',str(o/'live.log'),'full_display_work.tb_full_display','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s;print('\n'.join(l for l in s.splitlines() if 'PASS:' in l),flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f}
assert fh=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in fixtures}
(o/'result.json').write_text(json.dumps({'status':'PASS','component_spi_surrogate':True,'packet_boundary_surrogate':True,'full_saved_bmp_sources':True,'verified_720p_pixels':2764800,'source_hashes':h,'fixture_hashes':fh,'observations':[x for x in s.splitlines() if 'PASS:' in x or 'TRACE:' in x]},indent=2))
