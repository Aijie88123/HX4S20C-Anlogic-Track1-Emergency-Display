"""Source-bound regression for the production FAT/BMP reader and prefilter."""
from pathlib import Path
import subprocess, hashlib, json, sys
from datetime import datetime, timezone
ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/modelsim/win64')
OUT=ROOT/'evidence/media_reliable_20261013/tests'
SD=ROOT/'A_display/vendor/user_source/hdl_source/SD'
files=[SD/n for n in ['bmp_read.v','sd_card_bmp.v','sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v']]
files += [ROOT/'A_display/rtl/bmp_write_scaler.v',ROOT/'A_display/vendor/user_source/hdl_source/key_remove_shakes.v',
 ROOT/'tests/card_spi_named_media.v']
benches=[ROOT/'tests'/n for n in ['tb_reliable_media.v','tb_named_media_chain.v','tb_scaler_prefilter.v','tb_fat_geometry.v']]
for flag in [[],['--small']]:
 subprocess.run([sys.executable,'-B',str(ROOT/'tests/generate_media_vectors.py'),*flag],check=True)
fixtures=[p for d in ['media_vectors','media_vectors_small'] for p in (ROOT/'tests'/d).glob('*') if p.is_file()]
deps=sorted(set(files+benches+fixtures+[Path(__file__).resolve(),ROOT/'tests/generate_media_vectors.py']))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def snapshot():return [{'path':p.relative_to(ROOT).as_posix(),'sha256':sha(p)} for p in deps]
inputs=snapshot();OUT.mkdir(parents=True,exist_ok=True)
work=OUT/'work'
if work.exists():
 import shutil
 assert work.resolve().parent==OUT.resolve() and work.name=='work'
 shutil.rmtree(work)
logs=[]
def command(args):
 p=subprocess.run([str(a) for a in args],cwd=ROOT/'tests',stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=600)
 text=p.stdout.decode('utf-8',errors='replace');logs.append(text)
 if p.returncode or any(t in text for t in ['** Error','** Fatal','Error loading design','FAIL:']):
  (OUT/'audit.log').write_text('\n'.join(logs),encoding='utf-8');raise RuntimeError(text[-3500:])
 return text
command([MS/'vlib.exe',work]);command([MS/'vmap.exe','reliable_work',work]);command([MS/'vlog.exe','-work','reliable_work',*files])
command([MS/'vlog.exe','-sv','-work','reliable_work',*benches])
tests=[]
for top,parameters in [('tb_reliable_media',[]),('tb_named_media_chain',[]),('tb_named_media_chain',['-gMISSING_TWO=1']),('tb_named_media_chain',['-gFAULT_CHECK=1']),('tb_scaler_prefilter',[]),('tb_fat_geometry',[])]:
 text=command([MS/'vsim.exe','-c',*parameters,'reliable_work.'+top,'-do','run -all; quit -f'])
 markers=[s for s in text.splitlines() if 'PASS:' in s]
 assert markers,(top,'No completion marker')
 tests.append({'name':top,'parameters':parameters,'passed':True,'markers':markers})
 print(json.dumps(tests[-1]),flush=True)
assert inputs==snapshot(),'Sources changed during regression'
(OUT/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
(OUT/'result.json').write_text(json.dumps({'status':'PASS','tests':tests,'compiled_sources':inputs,
 'completed_utc':datetime.now(timezone.utc).isoformat()},indent=2),encoding='utf-8')
