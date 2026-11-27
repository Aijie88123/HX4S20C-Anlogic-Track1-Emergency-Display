from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parents[1];O=R/'evidence/true3d_map_20261018/legacy_controls';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work'
F=[R/'A_display/rtl/a_media_cached_control.v',R/'A_display/vendor/user_source/hdl_source/SD/sd_card_bmp.v',R/'tests/tb_dual_prev_controls.v']
H={str(p.relative_to(R)):hashlib.sha256(p.read_bytes()).hexdigest() for p in F};logs=[]
for cmd in [[str(M/'vlib.exe'),'work'],[str(M/'vlog.exe'),'-sv','-work','work',*map(str,F)],
 [str(M/'vsim.exe'),'-c','work.tb_dual_prev_controls','-do','onerror {quit -code 1}; run -all; quit -code 0']]:
 p=subprocess.run(cmd,cwd=O,capture_output=True,text=True,errors='replace',timeout=120);s=p.stdout+p.stderr;logs.append(s);(O/'audit.log').write_text('\n'.join(logs))
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-5000:])
assert 'PASS:' in s
assert H=={str(p.relative_to(R)):hashlib.sha256(p.read_bytes()).hexdigest() for p in F}
rows=[x for x in s.splitlines() if 'PASS:' in x];print('\n'.join(rows));(O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':H,'observations':rows},indent=2))
