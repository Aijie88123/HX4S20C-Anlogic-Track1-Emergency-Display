from pathlib import Path
import subprocess,hashlib,json
r=Path(__file__).resolve().parents[1];m=Path('D:/modelsim/win64');o=r/'evidence/true3d_map_20261018/packed_images';o.mkdir(parents=True,exist_ok=True);w=o/'work'
f=[r/'common/distributed_media.v',r/'A_display/rtl/a_media_cached_control.v',r/'A_display/vendor/user_source/hdl_source/SD/sd_card_bmp.v',r/'tests/tb_eight_packed_transport.v']
h={str(p.relative_to(r)):hashlib.sha256(p.read_bytes()).hexdigest() for p in f};logs=[]
ini=o/'modelsim.ini';ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
def run(tool,args):
 if tool in ['vmap','vlog','vsim']:args=['-modelsimini',ini.as_posix(),*args]
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=r,capture_output=True,timeout=1200);s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s)
 return s
if not w.exists():run('vlib',[str(w)])
run('vmap',['eight_packed_work',str(w)]);run('vlog',['-sv','-work',str(w),*map(str,f)])
try:
 for n in [60,307200]:
  s=run('vsim',['-c','eight_packed_work.tb_eight_packed_transport','-gN='+str(n),'-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
  (o/('media_'+str(n)+'.log')).write_text(s);print('\n'.join(l for l in s.splitlines() if 'PASS:' in l))
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p.relative_to(r)):hashlib.sha256(p.read_bytes()).hexdigest() for p in f}
(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h},indent=2))
