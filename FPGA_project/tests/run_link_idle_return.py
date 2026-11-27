from pathlib import Path
import subprocess, json, hashlib, threading, sys

root=Path(__file__).resolve().parents[1]
old=root
required=[root/'tests/storage_recovery_vectors'/(prefix+'_'+suffix)
          for prefix in ['small','full'] for suffix in ['expected.hex','sizes.hex','disk.hex']]
if not all(p.is_file() for p in required):
 subprocess.run([sys.executable,str(root/'tests/generate_storage_recovery_vectors.py')],check=True)
out=root/'evidence/tf_link_R6_20261016/idle_return'
out.mkdir(parents=True,exist_ok=True)
m=Path('D:/modelsim/win64');ini=out/'modelsim.ini'
ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
observations=[];hashes={}
def run(tool,args,log):
 with log.open('w',encoding='utf-8') as f:
  p=subprocess.Popen([str(m/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=root/'tests',stdout=f,stderr=subprocess.STDOUT)
  try:code=p.wait(timeout=900)
  except subprocess.TimeoutExpired:
   subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],capture_output=True);raise
 text=log.read_text(errors='replace')
 if code or '** Error' in text or '** Fatal' in text:raise RuntimeError(text[-7000:])
 return text
for label,src,cases in [('R5',old,[(1,1)]),('R6',root,[(1,0),(2,0),(3,0)])]:
 b=src/'B_control';sd=b/'vendor/user_source/hdl_source/SD';ip=b/'vendor/user_source/hdl_source/IP'
 sources=[sd/x for x in ['bmp_read.v','sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v','frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v']]
 sources += [b/'rtl'/x for x in ['b_media_storage.v','bmp_write_scaler.v','memory_startup_reset.v','ethernet_mailbox.v','remote_tf_sector.v']]
 sources += [ip/x for x in ['afifo_16_32_256.v','afifo_32_16_256.v']]
 sources += [root/'tests/card_spi_storage_recovery.v',root/'tests/tb_link_idle_return.v',Path('D:/td_extract/5E781D7/sim_release/eg4/eg_logic_bram.v')]
 if label=='R5':
  sources=[root/'tests/baseline_R5'/f.name if f.name in ('bmp_read.v','b_media_storage.v') else f for f in sources]
 hashes.update({str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources})
 work=out/('work_'+label)
 if not work.exists():run('vlib',[work],out/(label+'_vlib.log'))
 run('vmap',['-modelsimini',ini,'idle_'+label,work],out/(label+'_map.log'))
 run('vlog',['-modelsimini',ini,'-sv','-work',work,*sources],out/(label+'_compile.log'))
 for cycles,expect in cases:
  log=out/(label+f'_pulse{cycles}.log')
  s=run('vsim',['-modelsimini',ini,'-c','idle_'+label+'.tb_link_idle_return','-gPULSE_CYCLES='+str(cycles),'-gEXPECT_OLD_ABORT='+str(expect),'-do','onerror {quit -code 1}; run -all; quit -code 0'],log)
  assert 'PASS:' in s
  rows=[line for line in s.splitlines() if 'PASS:' in line]
  observations.extend(rows);print(label,cycles,'\n'.join(rows),flush=True)
assert all(hashlib.sha256(Path(f).read_bytes()).hexdigest()==h for f,h in hashes.items())
(out/'result.json').write_text(json.dumps({'status':'PASS','fault_injection':True,'physical_hardware_cause_proven':False,
 'scope':'R5 same zero-byte fault2 reproduced; R6 1/2/3-clock false-ready indications cannot abort loading; six full normalized source frames checked in each R6 run',
 'verified_R6_normalized_pixels':3*1843200,'source_hashes':hashes,'observations':observations},indent=2))
