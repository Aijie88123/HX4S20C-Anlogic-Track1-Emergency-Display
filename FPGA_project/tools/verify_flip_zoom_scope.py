from pathlib import Path
import hashlib,json,re
R=Path(__file__).resolve().parents[1];P=Path('D:/HX4S20C_transition_trim_20261023')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
dirs=['A_display/rtl','B_control/rtl','common','A_display/constraints','B_control/constraints','A_display/ip','B_control/ip','A_display/vendor','B_control/vendor','A_display/project','B_control/project']
ext={'.v','.vh','.sv','.svh','.adc','.sdc','.tcl','.cfg','.prj','.mem','.hex','.mif','.ps1','.ipc','.xml'}
def inventory(root):return {f.relative_to(root).as_posix():sha(f) for d in dirs for f in (root/d).rglob('*') if f.is_file() and 'smart_terminal_Runs' not in f.parts and f.suffix.lower() in ext}
parent=inventory(P);current=inventory(R);assert parent.keys()==current.keys()
changed=sorted(k for k in parent if parent[k]!=current[k])
required={'A_display/rtl/transition_fx.v','A_display/rtl/smart_terminal_overlay_pipelined.v','A_display/rtl/smart_terminal_hw_top.v','A_display/rtl/video_scanout_720p.v','A_display/rtl/distributed_media.v',*[f'A_display/vendor/user_source/hdl_source/SD/{n}' for n in ['frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v']]}
assert set(changed) in [required,required|{'A_display/project/phy_settings.cfg'}],changed
if 'A_display/project/phy_settings.cfg' in changed:
 a=(P/'A_display/project/phy_settings.cfg').read_text(encoding='utf-8-sig');b=(R/'A_display/project/phy_settings.cfg').read_text(encoding='utf-8-sig')
 assert re.sub(r'place seed \d+','place seed SEED',a)==re.sub(r'place seed \d+','place seed SEED',b)
assert parent['A_display/constraints/timing.sdc']==current['A_display/constraints/timing.sdc']
for k in parent:
 if k.startswith(('B_control/','common/','A_display/ip/','A_display/constraints/')):assert parent[k]==current[k],k
# The original protected SDRAM controller/refresh implementation and all
# source mirrors are untouched. Only conditional burst-entry guards and
# their default-off wrapper ports were added to the three cleartext files.
for n in ['frame_fifo_read.v','frame_fifo_write.v']:
 rel='A_display/vendor/user_source/hdl_source/SD/'+n
 s=(R/rel).read_text(encoding='utf-8-sig')
 s=s.replace('    parameter ENABLE_GEOMETRY_GUARD  = 0,\n','')
 s=re.sub(r'^    input geometry_guard,[ \t]*\n','',s,flags=re.M)
 if n=='frame_fifo_read.v':s=s.replace(' && (!(ENABLE_GEOMETRY_GUARD && geometry_guard) || (!Sdr_busy && !Sdr_init_ref_vld))','')
 else:s=s.replace(' &&\n      (!(ENABLE_GEOMETRY_GUARD && geometry_guard) || (!Sdr_busy && !Sdr_init_ref_vld))','')
 assert [v.rstrip() for v in s.splitlines()]==[v.rstrip() for v in (P/rel).read_text(encoding='utf-8-sig').splitlines()],n
phase=(R/'A_display/rtl/transition_fx.v').read_text(encoding='utf-8-sig');assert "3'd1: raw" not in phase and "3'd2: raw" not in phase
out=R/'evidence/flip_zoom_20261024';out.mkdir(parents=True,exist_ok=True)
d=dict(status='PASS',parent=P.as_posix(),production_changes=changed,parent_production_hashes=parent,current_production_hashes=current,source_hashes={str(R/k):v for k,v in current.items()},runner_hashes={str(Path(__file__).resolve()):sha(Path(__file__))},scope='Direct trim parent, authorized blind deletion + flip/zoom; A-only scanout/controller/fast unpack and default-off geometry-only memory burst-entry guard. B/common/TF/network/audio/map/PLL/SDC and protected SDRAM/refresh unchanged. Normal read/write burst bodies restore exactly after removing conditional geometry gate.')
(out/'scope.json').write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS: all production inputs compared to trim; eight scoped A files plus optional placement seed; exact original normal burst bodies and all B/protected/clock/constraint inputs preserved')
