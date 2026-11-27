from pathlib import Path
import subprocess,hashlib,json
R=Path(__file__).resolve().parents[1];O=R/'evidence/coldstart_video_fix_20261019/tf_timing';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';INI=O/'modelsim.ini';INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
files=[R/'A_display/rtl/a_tf_sector_service_timed.v',R/'common/ethernet_mailbox.v',
 R/'tests/a_tf_sector_service_reference.v',R/'tests/tb_tf_service_timing_equivalence.v',Path(__file__).resolve()]
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files};logs=[];observations=[]
def run(tool,args):
 if tool!='vlib':args=['-modelsimini',INI.as_posix(),*args]
 p=subprocess.run([str(M/(tool+'.exe')),*[x.as_posix() if isinstance(x,Path) else str(x) for x in args]],cwd=O,capture_output=True,timeout=300)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs))
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-5000:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['tf_timing',W]);run('vlog',['-sv','-work',W,*files[:-1]])
for timeout in [1,2,31,4096]:
 s=run('vsim',['-c','tf_timing.tb_tf_service_timing_equivalence','-gTIMEOUT='+str(timeout),'-do','onerror {quit -code 1}; run -all; quit -code 0'])
 assert 'PASS:' in s;observations += [x for x in s.splitlines() if 'PASS:' in x]
assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
(O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':h,'observations':observations,'timeouts':[1,2,31,4096],'SD_surrogate_only_for_cycle_equivalence':True},indent=2))
print('\n'.join(observations),flush=True)
