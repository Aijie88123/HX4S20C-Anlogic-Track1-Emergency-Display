from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/3d_ui_smooth_20261018/text_equivalence';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';INI=O/'modelsim.ini';INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
files=[R/'A_display/rtl/text_overlay_8x8.v',T/'text_overlay_8x8_reference.v',T/'tb_text_equivalence.v'];sources=files+[Path(__file__).resolve()];h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources};logs=[]
def run(n,args):
 p=subprocess.run([str(M/(n+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=T,capture_output=True,timeout=600)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-5000:])
 return s
try:
 if not W.exists():run('vlib',[W])
 run('vmap',['-modelsimini',INI,'text_equiv',W]);run('vlog',['-modelsimini',INI,'-sv','-work',W,*files]);s=run('vsim',['-modelsimini',INI,'-c','text_equiv.tb_text_equivalence','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
 assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
 obs=[v for v in s.splitlines() if 'PASS:' in v];(O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':obs,'pixels':3686400},indent=2));print('\n'.join(obs),flush=True)
finally:(O/'audit.log').write_text('\n'.join(logs))
