from pathlib import Path
import subprocess,hashlib,json,sys
r=Path(__file__).resolve().parents[1];m=Path('D:/modelsim/win64');o=r/'evidence/gif_sequence_20261015/simulation';o.mkdir(parents=True,exist_ok=True)
w=o/'work';ini=o/'modelsim.ini';ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
sources=[r/'A_display/rtl/a_media_cached_control.v',r/'A_display/vendor/user_source/hdl_source/SD/sd_card_bmp.v',
 r/'B_control/rtl/b_animation_cache.v',r/'common/raster_map_transport.v',r/'A_display/rtl/map_received_scanout.v',
 r/'tests/tb_animation_sequence.v']
if (r/'tests/tb_animation_transport.v').exists():sources+=[r/'tests/tb_animation_transport.v',r/'tests/tb_animation_kind.v']
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources};logs=[]
def run(tool,args):
 p=subprocess.run([str(m/(tool+'.exe')),*args],cwd=r/'tests',capture_output=True,timeout=1200)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-10000:])
 return s
try:
 if not w.exists():run('vlib',[w.as_posix()])
 run('vmap',['-modelsimini',ini.as_posix(),'animation_work',w.as_posix()])
 run('vlog',['-modelsimini',ini.as_posix(),'-sv','-work',w.as_posix(),*map(str,sources)])
 results=[]
 for name in (['tb_animation_transport'] if '--transport-only' in sys.argv else ['tb_animation_sequence','tb_animation_kind']+(['tb_animation_transport'] if len(sources)>6 else [])):
  s=run('vsim',['-modelsimini',ini.as_posix(),'-c','-l',str(o/(name+'.log')),'animation_work.'+name,'-do','onerror {quit -code 1}; run -all; quit -code 0'])
  assert 'PASS:' in s;results.extend(l for l in s.splitlines() if 'PASS:' in l or 'MEASURE:' in l);print('\n'.join(results),flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':results},indent=2))
