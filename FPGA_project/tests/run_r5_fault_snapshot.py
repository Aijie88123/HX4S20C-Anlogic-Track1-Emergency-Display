from pathlib import Path
import subprocess,json,hashlib
r=Path(__file__).resolve().parents[1];b=r/'B_control';a=r/'A_display';sd=b/'vendor/user_source/hdl_source/SD';ip=b/'vendor/user_source/hdl_source/IP';m=Path('D:/modelsim/win64');o=r/'evidence/tf_link_R6_20261016/fault_snapshot';o.mkdir(parents=True,exist_ok=True);w=o/'work';ini=o/'modelsim.ini';ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
f=[r/'common'/n for n in ['remote_tf_sector.v','ethernet_mailbox.v']]+[sd/n for n in ['bmp_read.v','sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v','frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v']]+[b/'rtl'/n for n in ['b_media_storage.v','bmp_write_scaler.v','memory_startup_reset.v']]+[ip/n for n in ['afifo_16_32_256.v','afifo_32_16_256.v']]+[r/'tests'/n for n in ['card_spi_real_full.v','tf_memory_models.v','tb_r5_fault_snapshot.v']]+[Path('D:/td_extract/5E781D7/sim_release/eg4/eg_logic_bram.v')];h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f};logs=[]
def run(t,args):
 p=subprocess.run([str(m/(t+'.exe')),*args],cwd=r/'tests',capture_output=True,timeout=180);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Fatal' in s or '** Error' in s:raise RuntimeError(s[-9000:])
 return s
try:
 if not w.exists():run('vlib',[w.as_posix()])
 run('vmap',['-modelsimini',ini.as_posix(),'r5_snapshot',w.as_posix()]);run('vlog',['-modelsimini',ini.as_posix(),'-sv','-work',w.as_posix(),*map(str,f)])
 s=run('vsim',['-modelsimini',ini.as_posix(),'-c','r5_snapshot.tb_r5_fault_snapshot','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s;observations=[l for l in s.splitlines() if 'PASS:' in l];print('\n'.join(observations))
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f}
(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':observations,'deliberate_fault_injection':True,'hardware_fault_C_reproduced':False,'byte_SPI_surrogate':True},indent=2))
