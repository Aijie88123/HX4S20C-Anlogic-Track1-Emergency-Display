from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parents[1];O=R/'evidence/coldstart_video_fix_20261019/order';O.mkdir(parents=True,exist_ok=True)
M=Path('D:/modelsim/win64');W=O/'work';INI=O/'modelsim.ini';INI.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
files=[R/'common/distributed_media.v',R/'A_display/rtl/a_media_cached_control.v',R/'A_display/vendor/user_source/hdl_source/SD/sd_card_bmp.v',R/'tests/tb_coldstart_order.v',Path(__file__).resolve()]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
snapshot={str(p):sha(p) for p in files};logs=[];observations=[]
def run(tool,args):
 if tool!='vlib':args=['-modelsimini',INI.as_posix(),*args]
 p=subprocess.run([str(M/(tool+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in args]],cwd=R,capture_output=True,timeout=180)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs))
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-5000:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['bootorder',W]);run('vlog',['-sv','-work',W,*files[:-1]])
for order in [0,1,2]:
 s=run('vsim',['-c','bootorder.tb_coldstart_order','-gN=60','-gORDER='+str(order),'-do','onerror {quit -code 1}; run -all; quit -code 0'])
 assert 'PASS:' in s;observations += [x for x in s.splitlines() if 'PASS:' in x or 'MEASURE boot order' in x]
assert snapshot=={str(p):sha(p) for p in files}
(O/'result.json').write_text(json.dumps({'status':'PASS','source_hashes':snapshot,'observations':observations,
 'scope':'Production media sender/receiver/cache-control protocol, compact 60-pixel frames and behavioral RAM source; physical card/HDMI and actual power supply sequencing not modeled'},indent=2))
print('\n'.join(observations),flush=True)
