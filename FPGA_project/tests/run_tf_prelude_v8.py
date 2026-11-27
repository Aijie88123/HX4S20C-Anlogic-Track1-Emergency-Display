from pathlib import Path
import subprocess,json,hashlib
r=Path(__file__).resolve().parents[1];m=Path('D:/modelsim/win64');o=r/'evidence/TF_link_fix_20261014/prelude';o.mkdir(parents=True,exist_ok=True);w=o/'work'
f=[r/'A_display/rtl/a_media_cached_control.v',r/'A_display/vendor/user_source/hdl_source/SD/sd_card_bmp.v',r/'A_display/rtl/map_received_scanout.v',r/'tests/tb_tf_prelude_v8.v',r/'common/ethernet_mailbox.v',r/'common/ethernet_frame_tx.v',r/'common/ethernet_frame_rx.v']
h={str(p.relative_to(r)):hashlib.sha256(p.read_bytes()).hexdigest() for p in f};logs=[]
def run(tool,args):
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=r/'tests',capture_output=True,timeout=180);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-5000:])
 return s
try:
 if not w.exists():run('vlib',[str(w)])
 run('vmap',['tf_prelude_work',str(w)]);run('vlog',['-sv','-work',str(w),*map(str,f)])
 s=run('vsim',['-c','tf_prelude_work.tb_tf_prelude_v8','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
 print('\n'.join(l for l in s.splitlines() if 'PASS:' in l))
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p.relative_to(r)):hashlib.sha256(p.read_bytes()).hexdigest() for p in f}
(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h},indent=2))
