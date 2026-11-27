from pathlib import Path
import json,hashlib,subprocess
R=Path(__file__).resolve().parents[1];T=R/'tests';O=R/'evidence/3d_ui_smooth_20261018/protocol';O.mkdir(parents=True,exist_ok=True)
W=O/'work';M=Path('D:/modelsim/win64');INI=O/'modelsim.ini';INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
f=[R/'common/ethernet_frame_tx.v',R/'common/ethernet_frame_rx.v',T/'tb_mesh3d_boundary.v'];logs=[]
def run(tool,args):
 if tool in ['vmap','vlog','vsim']:args=['-modelsimini',INI.as_posix(),*map(str,args)]
 p=subprocess.run([str(M/(tool+'.exe')),*map(str,args)],cwd=T,capture_output=True,timeout=120)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-5000:])
 return s
try:
 if not W.exists():run('vlib',[W])
 run('vmap',['mesh_boundary',W]);run('vlog',['-sv','-work',W,*f]);observations=[]
 for b in [0,1]:
  s=run('vsim',['-c','mesh_boundary.tb_mesh3d_boundary','-gSOURCE_B='+str(b),'-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
  observations += [x for x in s.splitlines() if 'PASS:' in x]
 (O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in f+[Path(__file__).resolve()]},'observations':observations},indent=2))
 print('\n'.join(observations))
finally:(O/'audit.log').write_text('\n'.join(logs))
