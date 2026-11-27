from pathlib import Path
import subprocess,hashlib,json
R=Path(__file__).resolve().parents[1];O=R/'evidence/coldstart_video_fix_20261019/video';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';INI=O/'modelsim.ini';INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
files=[R/'A_display/rtl/smart_terminal_hw_top.v',R/'A_display/vendor/user_source/hdl_source/video_rgb_to_axis_720p.v',
 R/'A_display/rtl/video_scanout_720p.v',R/'tests/tb_hdmi_startup_guard.v',R/'tests/tb_video_axis_720p.v',
 R/'tests/tb_startup_display_qualifier.v',R/'tests/tb_startup_display_scanout.v',
 R/'A_display/rtl/transition_fx.v',R/'tests/tb_transition_phase_equivalence.v',Path(__file__).resolve()]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
snapshot={str(p):sha(p) for p in files};logs=[];observations=[]
def run(tool,args):
 if tool!='vlib':args=['-modelsimini',INI.as_posix(),*args]
 p=subprocess.run([str(M/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=O,capture_output=True,timeout=300)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs))
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-5000:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['coldstart_video',W]);run('vlog',['-sv','-timescale','1ns/1ps','-work',W,*files[:-1]])
for top,args in [('tb_transition_phase_equivalence',[]),('tb_startup_display_qualifier',[]),('tb_startup_display_scanout',[]),('tb_hdmi_startup_guard',[]),('tb_hdmi_startup_guard',['-gSETTLE=3','-gUNLOCK=7']),('tb_video_axis_720p',[])]:
 s=run('vsim',['-c','coldstart_video.'+top,*args,'-do','onerror {quit -code 1}; run -all; quit -code 0'])
 assert 'PASS:' in s;observations += [v for v in s.splitlines() if 'PASS:' in v]
assert snapshot=={str(p):sha(p) for p in files}
(O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':snapshot,'observations':observations,'HDMI_sink_or_encrypted_core_model_not_available':True},indent=2))
print('\n'.join(observations),flush=True)
