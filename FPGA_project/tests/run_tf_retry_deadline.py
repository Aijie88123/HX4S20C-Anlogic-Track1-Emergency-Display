from pathlib import Path
import subprocess, json, hashlib
r=Path(__file__).resolve().parents[1];t=r/'tests';m=Path('D:/modelsim/win64')
out=r/'evidence/true3d_map_20261018/retry_deadline';out.mkdir(parents=True,exist_ok=True)
sd=r/'A_display/vendor/user_source/hdl_source/SD'
common=[r/'common'/n for n in ['ethernet_mailbox.v','ethernet_frame_tx.v','ethernet_frame_rx.v']]
common += [sd/n for n in ['sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v','spi_master.v']]
common += [t/'card_spi_real_capture.v',t/'tb_tf_retry_deadline.v']
sources=common+[t/'remote_tf_retry_baseline.v',t/'bmp_read_retry_baseline.v',r/'common/remote_tf_sector.v',r/'B_control/vendor/user_source/hdl_source/SD/bmp_read.v']
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources};logs=[];observations=[]
INI3D=out/'modelsim.ini';INI3D.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
def run(tool,args):
 if tool in ['vmap','vlog','vsim']:args=['-modelsimini',INI3D.as_posix(),*args]
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=t,capture_output=True,timeout=300)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-7000:])
 return s
try:
 for before in [1,0]:
  w=out/('before_work' if before else 'after_work');lib='retry_deadline_before' if before else 'retry_deadline_after'
  if not w.exists():run('vlib',[str(w)])
  run('vmap',[lib,str(w)])
  f=common+([t/'remote_tf_retry_baseline.v',t/'bmp_read_retry_baseline.v'] if before else [r/'common/remote_tf_sector.v',r/'B_control/vendor/user_source/hdl_source/SD/bmp_read.v'])
  run('vlog',['-sv','-work',str(w),*map(str,f)])
  s=run('vsim',['-c',lib+'.tb_tf_retry_deadline','-gEXPECT_FAILURE='+str(before),'-do','onerror {quit -code 1}; run -all; quit -code 0'])
  assert 'PASS:' in s
  observations += [line for line in s.splitlines() if 'TRACE:' in line or 'PASS:' in line]
  print('\n'.join(observations[-4:]),flush=True)
finally:(out/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
assert hashes=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
(out/'result.json').write_text(json.dumps({'status':'PASS','production_defaults_used':True,'physical_spi':True,'v8_mac_crc_ifg':True,'source_hashes':hashes,'observations':observations},indent=2))
