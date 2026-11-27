from pathlib import Path
import subprocess,json,hashlib
r=Path(__file__).resolve().parents[1];m=Path('D:/modelsim/win64');o=r/'evidence/TF_link_fix_20261014/physical_six_storage';o.mkdir(parents=True,exist_ok=True);w=o/'work';b=r/'B_control';sd=b/'vendor/user_source/hdl_source/SD';ip=b/'vendor/user_source/hdl_source/IP'
f=[sd/n for n in ['bmp_read.v','sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v','spi_master.v','frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v']]
f += [b/'rtl'/n for n in ['b_media_storage.v','bmp_write_scaler.v','memory_startup_reset.v','ethernet_mailbox.v','remote_tf_sector.v']]
f += [ip/n for n in ['afifo_16_32_256.v','afifo_32_16_256.v']]
f += [r/'tests/card_spi_physical_six.v',r/'tests/tb_physical_six_storage.v',Path('D:/td_extract/5E781D7/sim_release/eg4/eg_logic_bram.v')]
assert [p for p in f if 'module spi_master' in p.read_text()]==[sd/'spi_master.v']
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f};logs=[]
fixtures=[r/'tests/six_vectors_small/disk.hex']
fh={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in fixtures}
def run(tool,args):
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=r/'tests',capture_output=True,timeout=900);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s)
 return s
try:
 if not w.exists():run('vlib',[str(w)])
 run('vmap',['physical_six_storage_work',str(w)])
 run('vlog',['-sv','-work',str(w),*map(str,f)])
 s=run('vsim',['-c','-l',str(o/'live.log'),'physical_six_storage_work.tb_physical_six_storage','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s;print('\n'.join(l for l in s.splitlines() if 'PASS:' in l or 'TRACE:' in l),flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f}
assert fh=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in fixtures}
(o/'result.json').write_text(json.dumps({'status':'PASS','real_physical_spi':True,'byte_surrogate':False,'source_hashes':h,'fixture_hashes':fh,'observations':[x for x in s.splitlines() if 'PASS:' in x or 'TRACE:' in x]},indent=2))
