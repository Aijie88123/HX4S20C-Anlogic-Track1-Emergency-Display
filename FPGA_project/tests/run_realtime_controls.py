from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/true3d_map_20261018/controls';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';INI=O/'modelsim.ini';INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
files=[R/'A_display/rtl/a_media_cached_control.v',R/'A_display/vendor/user_source/hdl_source/SD/sd_card_bmp.v',T/'tb_realtime_controls.v'];logs=[]
def run(tool,args):
 p=subprocess.run([str(M/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=T,capture_output=True,timeout=120)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6000:])
 return s
try:
 if not W.exists():run('vlib',[W])
 run('vmap',['-modelsimini',INI,'control_work',W]);run('vlog',['-modelsimini',INI,'-sv','-work',W,*files])
 s=run('vsim',['-modelsimini',INI,'-c','control_work.tb_realtime_controls','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
 rows=[l for l in s.splitlines() if 'PASS:' in l];print('\n'.join(rows))
finally:(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
(O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},'observations':rows},indent=2))
