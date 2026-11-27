from pathlib import Path
import subprocess,hashlib,json
R=Path(__file__).resolve().parents[1];O=R/'evidence/audio_visual_seamless_20261022/video720';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';INI=O/'modelsim.ini';INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
files=[R/'A_display/rtl/smart_terminal_hw_top.v',R/'A_display/rtl/video_scanout_720p.v',R/'A_display/vendor/user_source/hdl_source/video_rgb_to_axis_720p.v',R/'tests/tb_boot_video720.v',Path(__file__).resolve()]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
hashes={str(p):sha(p) for p in files};logs=[]
def run(tool,args):
 if tool!='vlib':args=['-modelsimini',INI.as_posix(),*args]
 p=subprocess.run([str(M/(tool+'.exe')),*map(str,args)],cwd=O,capture_output=True,timeout=600)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6000:])
 return s
if not W.exists():run('vlib',[W.as_posix()])
run('vmap',['bootvideo720',W.as_posix()]);run('vlog',['-sv','-timescale','1ns/1ps','-work',W.as_posix(),*[p.as_posix() for p in files[:-1]]])
s=run('vsim',['-c','bootvideo720.tb_boot_video720','-do','onerror {quit -code 1}; run -all; quit -code 0'])
assert 'PASS:' in s
assert hashes=={str(p):sha(p) for p in files}
observations=[v for v in s.splitlines() if 'PASS:' in v]
(O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':hashes,'observations':observations,'scope':'Actual scanout and converter; behavioral SDRAM constant pixels and interface-ready/lock injection, no encrypted HDMI core or physical sink model'},indent=2),encoding='utf-8')
print('\n'.join(observations),flush=True)
