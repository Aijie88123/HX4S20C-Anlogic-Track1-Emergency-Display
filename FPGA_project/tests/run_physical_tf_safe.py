from pathlib import Path
import subprocess,json,hashlib
r=Path(__file__).resolve().parents[1];m=Path('D:/modelsim/win64');o=r/'evidence/true3d_map_20261018/physical_spi';o.mkdir(parents=True,exist_ok=True);w=o/'work';sd=r/'A_display/vendor/user_source/hdl_source/SD'
f=[r/'common'/n for n in ['remote_tf_sector.v','ethernet_mailbox.v','ethernet_frame_tx.v','ethernet_frame_rx.v']]+[sd/n for n in ['sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v','spi_master.v']]+[r/'tests/card_spi_physical_tf.v',r/'tests/tb_physical_tf_safe.v']
assert [p for p in f if 'module spi_master' in p.read_text()]==[sd/'spi_master.v'], 'Physical test must compile production SPI master, never a byte surrogate'
f += [r/'A_display/rtl/a_tf_sector_service_timed.v']
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f};logs=[]
INI3D=o/'modelsim.ini';INI3D.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
def run(tool,args):
 if tool in ['vmap','vlog','vsim']:args=['-modelsimini',INI3D.as_posix(),*args]
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=r/'tests',capture_output=True,timeout=600);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-7000:])
 return s
try:
 if not w.exists():run('vlib',[str(w)])
 run('vmap',['physical_safe_work',str(w)]);run('vlog',['-sv','-work',str(w),*map(str,f)])
 observations=[]
 for mode in [0,1,2]:
  s=run('vsim',['-c','physical_safe_work.tb_physical_tf_safe','-gFAST_MODE='+str(mode),'-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
  observations.extend(x for x in s.splitlines() if 'PASS:' in x or 'TRACE:' in x)
  print('\n'.join(x for x in s.splitlines() if 'PASS:' in x),flush=True)
 print('\n'.join(x for x in s.splitlines() if 'PASS:' in x or 'TRACE:' in x),flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f}, 'Source changed during test'
(o/'result.json').write_text(json.dumps({'status':'PASS','real_physical_spi':True,'spi_mhz':6.25,'byte_surrogate':False,'source_hashes':h,'modes':[0,1,2],'observations':observations},indent=2))
