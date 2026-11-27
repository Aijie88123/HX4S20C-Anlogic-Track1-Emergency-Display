from pathlib import Path
import subprocess, hashlib, json
r=Path(__file__).resolve().parents[1];o=r/'evidence/startup_optimized_20261014/ui';o.mkdir(parents=True,exist_ok=True);m=Path('D:/modelsim/win64');w=o/'work'
files=[r/'A_display/rtl/text_overlay_8x8.v',r/'tests/tb_startup_ui.v']
bound=files+[r/'A_display/rtl/smart_terminal_hw_top.v',r/'A_display/rtl/smart_terminal_overlay_pipelined.v',r/'common/distributed_media.v']
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in bound};logs=[]
top=(bound[2]).read_text();assert '.ENABLE_STARTUP_UI (ENABLE_MEDIA)' in top and '.receive_progress(startup_progress_net)' in top and '.src_data(startup_progress_net)' in top and "ENABLE_MEDIA ? 24'h0b1e30" in top
def run(tool,args):
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=o,capture_output=True,timeout=300);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-5000:])
 return s
try:
 run('vlib',[str(w)]);run('vmap',['startup_ui_work',str(w)]);run('vlog',['-sv','-work',str(w),*map(str,files)])
 s=run('vsim',['-c','startup_ui_work.tb_startup_ui','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in bound}
out={'status':'PASS','source_hashes':h,'observations':[l for l in s.splitlines() if 'PASS:' in l]}
(o/'result.json').write_text(json.dumps(out,indent=2));print(out['observations'])
