from pathlib import Path
import subprocess,json,hashlib
r=Path(__file__).resolve().parents[1];m=Path('D:/modelsim/win64');o=r/'evidence/real_card_fix_20261015/physical_scan';o.mkdir(parents=True,exist_ok=True);w=o/'work';sd=r/'A_display/vendor/user_source/hdl_source/SD'
f=[r/'common'/n for n in ['remote_tf_sector.v','ethernet_mailbox.v','ethernet_frame_tx.v','ethernet_frame_rx.v']]+[sd/n for n in ['sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v','spi_master.v']]+[r/'tests/card_spi_real_capture.v',r/'tests/tb_real_card_physical_scan.v',r/'B_control/vendor/user_source/hdl_source/SD/bmp_read.v']
assert [p for p in f if 'module spi_master' in p.read_text()]==[sd/'spi_master.v'], 'Physical test must compile production SPI master, never a byte surrogate'
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f};logs=[]
def run(tool,args):
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=r/'tests',capture_output=True,timeout=600);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-7000:])
 return s
try:
 if not w.exists():run('vlib',[str(w)])
 run('vmap',['real_card_physical_work',str(w)]);run('vlog',['-sv','-work',str(w),*map(str,f)])
 observations=[]
 for delay in [22,60]:
  s=run('vsim',['-c','real_card_physical_work.tb_real_card_physical_scan','-gMISO_DELAY_NS='+str(delay),'-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
  observations += [str(delay)+'ns: '+x for x in s.splitlines() if 'PASS:' in x]
  print('\n'.join(observations[-1:]),flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f}, 'Source changed during test'
(o/'result.json').write_text(json.dumps({'status':'PASS','real_physical_spi':True,'byte_surrogate':False,'source_hashes':h,'spi_mhz':6.25,'synthetic_miso_delay_ns':[22,60],'observations':observations,'fixture_hashes':{str(x):hashlib.sha256(x.read_bytes()).hexdigest() for x in [r/'tests/real_card_vectors/lbas.hex',r/'tests/real_card_vectors/sectors.bin']}},indent=2))
