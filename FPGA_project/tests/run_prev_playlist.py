from pathlib import Path
import hashlib,json,subprocess,sys
from datetime import datetime,timezone
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'evidence/dual_prev_playlist_20261017/tests'
MS=Path('D:/modelsim/win64')
sources=[ROOT/'B_control/vendor/user_source/hdl_source/SD/bmp_read.v',ROOT/'tests/tb_prev_playlist_scan.v']
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
success=True
for case in ['real_card','shuffled_one_cluster','shuffled_multicluster','bad_alarm_header','missing_directory']:
 vectors=ROOT/'tests/prev_playlist_vectors'/case;meta=json.loads((vectors/'meta.json').read_text())
 d=OUT/('named_'+case);d.mkdir(parents=True,exist_ok=True)
 dependencies=sources+sorted(vectors.glob('*'))
 snapshot=[{'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':digest(p)} for p in dependencies]
 commands=[[str(MS/'vlib.exe'),'work'],[str(MS/'vlog.exe'),'-work','work']+[str(p) for p in sources],
 [str(MS/'vsim.exe'),'-c','work.tb_prev_playlist_scan','+VECTORS='+str(vectors).replace('\\','/'),'+SECTORS='+str(meta['sectors']),'+COUNT='+str(meta['expected_count']),'-do','run -all; quit -f']]
 output=''
 for cmd in commands:
  p=subprocess.run(cmd,cwd=d,capture_output=True,text=True,errors='replace',timeout=90);output+=p.stdout+p.stderr
  if p.returncode:break
 markers=[x for x in output.splitlines() if 'PASS:' in x or 'FAIL:' in x or '** Error' in x or '** Fatal' in x or 'Error loading design' in x]
 status='PASS' if p.returncode==0 and any('PASS:' in x for x in markers) and not any('FAIL:' in x or '** Error' in x or '** Fatal' in x or 'Error loading design' in x for x in markers) else 'FAIL'
 assert all(digest(ROOT/x['path'])==x['sha256'] for x in snapshot)
 (d/'audit.log').write_text(output,encoding='utf-8')
 (d/'result.json').write_text(json.dumps({'status':status,'test':case,'markers':markers,'compiled_sources':snapshot,'completed_utc':datetime.now(timezone.utc).isoformat()},indent=2))
 print(json.dumps({'test':case,'status':status,'markers':markers}),flush=True);success &= status=='PASS'
sys.exit(0 if success else 1)
