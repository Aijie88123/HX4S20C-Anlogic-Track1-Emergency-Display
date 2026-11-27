from pathlib import Path
import subprocess,json,hashlib
r=Path(__file__).resolve().parents[1];m=Path('D:/modelsim/win64');o=r/'evidence/TF_on_A_20261014/sector';o.mkdir(parents=True,exist_ok=True);w=o/'work';sd=r/'A_display/vendor/user_source/hdl_source/SD'
f=[r/'common'/n for n in ['remote_tf_sector.v','ethernet_mailbox.v','ethernet_frame_tx.v','ethernet_frame_rx.v']]+[sd/n for n in ['sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v']]+[r/'tests/card_spi_storage.v',r/'tests/tb_remote_tf.v']
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f};logs=[]
def run(tool,args):
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=r/'tests',capture_output=True,timeout=300);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-7000:])
 return s
try:
 if not w.exists():run('vlib',[str(w)])
 run('vmap',['remote_tf_work',str(w)]);run('vlog',['-sv','-work',str(w),*map(str,f)])
 s=run('vsim',['-c','remote_tf_work.tb_remote_tf','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
 print('\n'.join(x for x in s.splitlines() if 'PASS:' in x),flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f};(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':[x for x in s.splitlines() if 'PASS:' in x]},indent=2))
