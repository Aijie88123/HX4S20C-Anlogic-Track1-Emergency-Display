from pathlib import Path
import subprocess,json,hashlib
r=Path(__file__).resolve().parents[1];o=r/'evidence/tf_link_R6_20261016/frame_counter';o.mkdir(parents=True,exist_ok=True);m=Path('D:/modelsim/win64');w=o/'work';ini=o/'modelsim.ini';ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
def run(t,args):
 p=subprocess.run([str(m/(t+'.exe')),*args],cwd=r/'tests',capture_output=True,timeout=300);s=(p.stdout+p.stderr).decode(errors='replace')
 if p.returncode or '** Fatal' in s or '** Error' in s:raise RuntimeError(s[-6000:])
 return s
if not w.exists():run('vlib',[w.as_posix()])
run('vmap',['-modelsimini',ini.as_posix(),'pixel_probe',w.as_posix()]);run('vlog',['-modelsimini',ini.as_posix(),'-sv','-work',w.as_posix(),str(r/'B_control/vendor/user_source/hdl_source/SD/bmp_read.v'),str(r/'tests/tb_frame_counter.v')])
sources=[r/'B_control/vendor/user_source/hdl_source/SD/bmp_read.v',r/'tests/tb_frame_counter.v'];h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources};results=[]
for fast,jitter in [(1,0),(1,1),(0,1)]:
 s=run('vsim',['-modelsimini',ini.as_posix(),'-c','pixel_probe.tb_frame_counter','-gFAST='+str(fast),'-gJITTER='+str(jitter),'-do','onerror {quit -code 1}; run -all; quit -code 0']);(o/f'f{fast}j{jitter}.log').write_text(s);results.extend(l for l in s.splitlines() if 'PASS:' in l);print(results[-1],flush=True)
(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':results,'hardware_fault_C_reproduced':False},indent=2))
