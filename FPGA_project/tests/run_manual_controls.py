from pathlib import Path
import subprocess,hashlib,json
r=Path(__file__).resolve().parents[1];o=r/'evidence/manual_controls_R10_20261016/controls';o.mkdir(parents=True,exist_ok=True)
m=Path('D:/modelsim/win64');w=o/'work';ini=o/'modelsim.ini';ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
files=[r/'A_display/rtl/a_media_cached_control.v',r/'A_display/vendor/user_source/hdl_source/SD/sd_card_bmp.v',r/'A_display/rtl/text_overlay_8x8.v',r/'tests/tb_manual_controls.v',r/'tests/tb_playback_osd.v',r/'tests/tb_animation_sequence.v']
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files};logs=[];observations=[]
def run(tool,args):
 if tool!='vlib':args=['-modelsimini',ini.as_posix(),*args]
 p=subprocess.run([str(m/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=r/'tests',capture_output=True,timeout=240)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-7000:])
 return s
try:
 if not w.exists():run('vlib',[w])
 run('vlog',['-sv','-work',w,*files])
 for top in ['tb_manual_controls','tb_playback_osd','tb_animation_sequence']:
  s=run('vsim',['-c','-lib',w,top,'-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
  rows=[v for v in s.splitlines() if 'PASS:' in v];observations+=rows;print('\n'.join(rows),flush=True)
finally:(o/'audit.log').write_text('\n'.join(logs))
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
(o/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':observations,'limits':'Control clock is accelerated to 1kHz for millisecond/button/timer tests; these are simulated latencies, not physical measurements.'},indent=2))
