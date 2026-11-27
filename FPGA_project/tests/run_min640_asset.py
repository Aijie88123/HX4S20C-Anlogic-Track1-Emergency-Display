from pathlib import Path
import subprocess,hashlib,json
R=Path(__file__).resolve().parents[1];O=R/'evidence/coldstart_video_fix_20261019/min640';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';INI=O/'modelsim.ini';INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
files=[R/'B_control/vendor/user_source/hdl_source/SD/bmp_read.v',R/'B_control/rtl/bmp_write_scaler.v',R/'tests/tb_min640_asset.v',Path(__file__).resolve(),
 R/'assets/tf_card/PREV_BMP/02INFO.BMP',*sorted((R/'tests/min640_vectors').glob('*'))]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
snapshot={str(p):sha(p) for p in files};logs=[];observations=[]
def run(tool,args):
 if tool!='vlib':args=['-modelsimini',INI.as_posix(),*args]
 p=subprocess.run([str(M/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=R/'tests',capture_output=True,timeout=600)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs))
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-4500:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['min640',W]);run('vlog',['-sv','-timescale','1ns/1ps','-work',W,*files[:3]])
for pacing in [4,24]:
 s=run('vsim',['-c','min640.tb_min640_asset','-gBYTE_PERIOD='+str(pacing),'-do','onerror {quit -code 1}; run -all; quit -code 0'])
 assert 'PASS:' in s;observations += [x for x in s.splitlines() if 'PASS:' in x];print('\n'.join(observations[-1:]),flush=True)
assert snapshot=={str(p):sha(p) for p in files}
(O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':snapshot,'observations':observations,'synthetic_card_layout_exact_BMP_not_physical_card_capture':True},indent=2))
