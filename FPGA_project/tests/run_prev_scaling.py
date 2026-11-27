from pathlib import Path
import subprocess,hashlib,json
r=Path(__file__).resolve().parents[1];o=r/'evidence/dual_prev_playlist_20261017/scaling';o.mkdir(parents=True,exist_ok=True);m=Path('D:/modelsim/win64');w=o/'work'
f=[r/'B_control/rtl/bmp_write_scaler.v',r/'tests/tb_prev_scaling.v'];bound=f+[r/'B_control/rtl/b_media_storage.v',r/'common/remote_tf_sector.v']
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in bound};logs=[];observations=[]
assert 'source_w>=320 && source_h>=240' in bound[2].read_text()
ini=o/'modelsim.ini';ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
def run(tool,args):
 if tool in ['vmap','vlog','vsim']:args=['-modelsimini',ini.as_posix(),*args]
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=o,capture_output=True,timeout=300);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-5000:])
 return s
try:
 run('vlib',[str(w)]);run('vmap',['scaler_pacing_work',str(w)]);run('vlog',['-sv','-work',str(w),*map(str,f)])
 for width,height in [(640,480),(427,321),(800,600),(1280,720)]:
  s=run('vsim',['-c','scaler_pacing_work.tb_prev_scaling','-gW='+str(width),'-gH='+str(height),'-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
  observations.extend(l for l in s.splitlines() if 'PASS:' in l);print(observations[-1],flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in bound}
(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'pixels':1228800,'observations':observations},indent=2))
