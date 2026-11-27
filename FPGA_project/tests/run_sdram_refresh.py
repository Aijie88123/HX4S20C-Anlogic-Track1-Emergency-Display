from pathlib import Path
import argparse,subprocess,hashlib,json
parser=argparse.ArgumentParser()
parser.add_argument('--board',choices=['A_display','B_control'],default='A_display')
parser.add_argument('--baseline',action='store_true')
parser.add_argument('--top',default='tb_sdram_refresh_retention')
args=parser.parse_args();root=Path(__file__).resolve().parents[1]
source=Path('D:/HX4S20C_coldstart_video_fix_20261019') if args.baseline else root
o=root/'evidence/emergency_cache_fix_20261020'/('baseline_' if args.baseline else 'fixed_')/args.board/args.top
o.mkdir(parents=True,exist_ok=True);m=Path('D:/modelsim/win64');w=o/'work'
ini=o/'modelsim.ini';ini.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n')
v=source/args.board/'vendor/user_source/hdl_source';td=Path('D:/td_extract/5E781D7/sim_release/eg4')
files=[v/'include'/x for x in ['sdr_init_ref.enc.v','sdr_wrrd.enc.v','sdr_as_ram.enc.v']]
files += [v/'SD'/x for x in ['sdram.v','frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v']]
files += [v/'IP/afifo_16_32_256.v',v/'IP/afifo_32_16_256.v',td/'eg_logic_bram.v',td/'eg_phy_sdram_2m_32.v',root/'tests/sdram_pin_model.v',root/'tests'/(args.top+'.v')]
sources=files+[v/'include/global_def.v',Path(__file__).resolve()]
h={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources};logs=[]
def run(name,argv):
 if name!='vlib':argv=['-modelsimini',ini.as_posix(),*argv]
 p=subprocess.run([str(m/(name+'.exe')),*argv],cwd=root/'tests',capture_output=True,timeout=1200)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s)
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-10000:])
 return s
try:
 if not w.exists():run('vlib',[w.as_posix()])
 run('vmap',['refresh_work',w.as_posix()])
 run('vlog',['-sv','+define+SIMULATION','+incdir+'+(v/'include').as_posix(),'-work',w.as_posix(),*map(str,files)])
 extra=['-gEXPECT_REFRESH='+('0' if args.baseline else '1')] if args.top=='tb_sdram_refresh_retention' else []
 s=run('vsim',['-c','refresh_work.'+args.top,*extra,'-do','onerror {quit -code 1}; run -all; quit -code 0'])
 assert 'PASS:' in s
 observations=[line for line in s.splitlines() if 'PASS:' in line or 'MEASURE:' in line]
 print('\n'.join(observations),flush=True)
 assert h=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
 (o/'result.json').write_text(json.dumps({'status':'PASS','baseline_bug_reproduced':args.baseline,'board':args.board,'source_hashes':h,'observations':observations,'physical_silicon_test':False,'pin_model':'independent functional BL4/CL3; no analog/retention fault injection'},indent=2),encoding='utf-8')
finally:(o/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
