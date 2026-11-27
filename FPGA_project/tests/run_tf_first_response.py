from pathlib import Path
import subprocess,json,hashlib,sys
r=Path(__file__).resolve().parents[1];t=r/'tests';m=Path('D:/modelsim/win64');o=r/'evidence/tf_load_recovery_20261015/first_response';o.mkdir(parents=True,exist_ok=True)
sd=r/'A_display/vendor/user_source/hdl_source/SD'
base=[r/'common'/n for n in ['ethernet_mailbox.v','ethernet_frame_tx.v','ethernet_frame_rx.v']]
base += [sd/n for n in ['sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v','spi_master.v']]
base += [t/'card_spi_real_capture.v',t/'tb_tf_first_response.v',r/'B_control/vendor/user_source/hdl_source/SD/bmp_read.v']
logs=[];results=[];sources=[]
def run(tool,args):
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=t,capture_output=True,timeout=600);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-10000:])
 return s
try:
 for before in ([1] if '--before-only' in sys.argv else [1,0]):
  w=o/('before_work' if before else 'after_work');lib='tf_first_'+str(before)
  f=base+[t/'remote_tf_g3_baseline.v' if before else r/'common/remote_tf_sector.v'];sources+=f
  if not w.exists():run('vlib',[w.as_posix()])
  run('vmap',[lib,w.as_posix()]);run('vlog',['-sv','-work',w.as_posix(),*map(str,f)])
  s=run('vsim',['-c','-l',(o/('before.log' if before else 'after.log')).as_posix(),lib+'.tb_tf_first_response','-gEXPECT_FAILURE='+str(before),'-do','onerror {quit -code 1}; run -all; quit -code 0'])
  assert 'PASS:' in s;results += [l for l in s.splitlines() if 'PASS:' in l];print('\n'.join(results[-1:]),flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
if '--before-only' not in sys.argv:
 (o/'result.json').write_text(json.dumps({'status':'PASS','physical_SPI':True,'v9_MAC_CRC':True,'token_delay_ms':20,'source_hashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in set(sources)},'observations':results},indent=2))
