from pathlib import Path
import subprocess,hashlib,json
r=Path(__file__).resolve().parents[1];o=r/'evidence/real_card_fix_20261015/diagnostics';o.mkdir(parents=True,exist_ok=True);m=Path('D:/modelsim/win64');w=o/'work'
sources=[r/'B_control/vendor/user_source/hdl_source/SD/bmp_read.v',r/'tests/tb_real_card_diagnostics.v'];h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources};logs=[];observations=[]
def run(tool,args):
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=r/'tests',capture_output=True,timeout=120);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 print('\n'.join(l for l in s.splitlines() if 'TRACE' in l or 'PASS' in l or 'FAIL' in l),flush=True)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6000:])
 return s
try:
 run('vlib',[str(w)]);run('vmap',['real_card_diagnostics_work',str(w)]);run('vlog',['-sv','-work',str(w),*map(str,sources)])
 for mode in [1,2,3,4]:
  s=run('vsim',['-c','real_card_diagnostics_work.tb_real_card_diagnostics','-gMODE='+str(mode),'-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS' in s;observations.extend(l for l in s.splitlines() if 'PASS' in l)
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':observations},indent=2))
