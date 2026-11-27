from pathlib import Path
import re,subprocess,hashlib,json,sys
R=Path(__file__).resolve().parents[1];F=R/'tests/reference_resource_timing';O=R/'evidence/resource_timing_20261025/rom_exact';O.mkdir(parents=True,exist_ok=True)
items=[('B_control','b_particle_shader'),('A_display','text_overlay_8x8'),('A_display','audio_spectrum_precise_overlay'),('A_display','audio_waveform_precise_overlay')]
files=[];support=[]
for board,name in items:
 original=F/(board+'_'+name+'.v');p=O/('ref_'+name+'.v');s=original.read_text(encoding='utf-8-sig');p.write_text(re.sub(r'\b'+name+r'\b','ref_resource_'+name,s),encoding='utf-8');files += [R/board/'rtl'/(name+'.v'),p];support.append(original)
files += [R/'A_display/rtl/audio_label_font_fast.v',R/'tests/tb_resource_roms.v']
files += [Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_bram32k.v'),Path('D:/td_extract/5E781D7/sim_release/eg4/eg_phy_glbl.v')]
bound=files+support+[R/'tools/generate_resource_roms.py',Path(__file__).resolve()];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();h={str(p):sha(p) for p in bound}
M=Path('D:/modelsim/win64');I=O/'modelsim.ini';I.write_text('[Library]\nothers = D:/modelsim/modelsim.ini\n');W=O/'work';logs=[]
def run(t,a):
 p=subprocess.run([str(M/(t+'.exe')),*[str(v).replace(chr(92),'/') for v in a]],cwd=O,capture_output=True,timeout=1800)
 s=(p.stdout+p.stderr).decode(errors='replace');logs.append(s);(O/'audit.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error' in s or '** Fatal' in s:raise RuntimeError(s[-6500:])
 return s
if not W.exists():run('vlib',[W])
run('vmap',['-modelsimini',I,'resource_roms',W]);run('vlog',['-modelsimini',I,'-sv','-work',W,*files])
obs=[]
tops=['tb_resource_particle_exact','tb_resource_text_exact','tb_resource_audio_exact']
if len(sys.argv)>1:tops=[sys.argv[1]]
for top in tops:
 print('RUN '+top,flush=True);s=run('vsim',['-modelsimini',I,'-c','-l',O/(top+'.log'),'resource_roms.'+top,'resource_roms.glbl','-do','onerror {quit -code 1}; run -all; quit -code 0']);assert 'PASS:' in s
 rows=[v for v in s.splitlines() if 'PASS:' in v];obs+=rows;print('\n'.join(rows),flush=True)
assert h=={str(p):sha(p) for p in bound}
(O/('result.json' if len(tops)==3 else tops[0]+'.json')).write_text(json.dumps(dict(status='PASS',source_hashes=h,observations=obs,scope='Exact frozen approved fast source compared cycle-for-cycle; compact ROM addresses also exhaustively compared. No shortened input handshake or raster timing.'),indent=2),encoding='utf-8')
