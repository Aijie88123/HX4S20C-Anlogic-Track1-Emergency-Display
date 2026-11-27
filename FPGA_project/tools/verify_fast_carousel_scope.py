from pathlib import Path
import hashlib,json,difflib
R=Path(__file__).resolve().parents[1];P=Path('D:/HX4S20C_map_abc_20261025');F=Path('D:/HX4S20C_scan_trace_20261024');O=R/'evidence/fast_carousel_20261025';O.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
dirs=['A_display/rtl','B_control/rtl','common','A_display/constraints','B_control/constraints','A_display/ip','B_control/ip','A_display/vendor','B_control/vendor','A_display/project','B_control/project'];ext={'.v','.vh','.sv','.svh','.adc','.sdc','.tcl','.cfg','.prj','.mem','.hex','.mif','.ps1','.ipc','.xml'}
def inv(root):return {p.relative_to(root).as_posix():sha(p) for d in dirs for p in (root/d).rglob('*') if p.is_file() and 'smart_terminal_Runs' not in p.parts and p.suffix.lower() in ext}
a,b,f=inv(P),inv(R),inv(F);assert a.keys()==b.keys()==f.keys();assert a==f
changed=sorted(k for k in a if a[k]!=b[k]);expected={
'A_display/rtl/smart_terminal_hw_top.v','A_display/rtl/a_media_cached_control.v','A_display/rtl/video_scanout_720p.v','A_display/rtl/smart_terminal_overlay_pipelined.v','A_display/rtl/text_overlay_8x8.v','B_control/rtl/dual_board_control_top.v'}
assert set(changed)==expected,changed
for k in ['A_display/vendor/user_source/hdl_source/include/sdr_init_ref.enc.v','A_display/project/phy_settings.cfg']:
 assert b[k]==f[k],k
for rel in ['assets/map_scene_presets.json','assets/map_scene_parameters.json','tools/resolve_map_scene.py','tools/generate_map_scene_parameters.py']:assert sha(R/rel)==sha(P/rel),rel
top=(R/'A_display/rtl/smart_terminal_hw_top.v').read_text(encoding='utf-8-sig')
assert 'else if(startup_display_ready)qualified_memory_guard<=1\'b1;' in top
assert '.geometry_mode(photo_geometry_active || qualified_memory_guard)' in top
assert '.PHASE_STEP(FAST_DEMO?2:1)' in top and '.NORMAL_PERIOD_MS(FAST_DEMO?350:3000)' in top and '.DEMO_FAST_PERIODS(FAST_DEMO)' in top
v=(R/'A_display/rtl/video_scanout_720p.v').read_text(encoding='utf-8-sig');old=(P/'A_display/rtl/video_scanout_720p.v').read_text(encoding='utf-8-sig')
restored=v.replace('module photo_geometry_control #(parameter integer PHASE_STEP=1)(', 'module photo_geometry_control(').replace(' localparam [5:0] PHASE_INC=PHASE_STEP;\n','').replace('phase<=phase+PHASE_INC','phase<=phase+1\'b1')
assert restored==old,'Geometry pixel/row/math paths must remain byte-identical; only control phase step changes'
src={str(R/k):v for k,v in b.items()}
for rel in ['assets/map_scene_presets.json','assets/map_scene_parameters.json','tools/resolve_map_scene.py','tools/generate_map_scene_parameters.py']:src[str(R/rel)]=sha(R/rel)
diff=''.join(''.join(difflib.unified_diff((P/k).read_text(encoding='utf-8-sig').splitlines(True),(R/k).read_text(encoding='utf-8-sig').splitlines(True),fromfile='map_abc/'+k,tofile='fast_carousel/'+k)) for k in changed)
(O/'production.diff').write_text(diff,encoding='utf-8')
d=dict(status='PASS',parent=str(P),previous_parent='flip_zoom_20261024',production_changes=changed,source_hashes=src,runner_hashes={str(Path(__file__).resolve()):sha(Path(__file__))},scope='Six production RTL files implement the matched A/B demo350/1000/2000ms profile, first3s B startup dwell, phase-step2 geometry and period OSD. The existing diagnostic code is retained but default-disabled. The selected map_abc and scan_trace production inputs are byte-identical; steady qualified busy/refresh guard and ACK edge deduplication are retained. No clocks, constraints, pins, encrypted blocks, TF/BMP, V12 packet formats, map, audio or geometry pixel/row math changed. Legacy inner parameter defaults retained.')
(O/'scope.json').write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('PASS: six RTL changes only; original clocks/constraints/SDRAM/FIFO/TF/map/audio and white-line fixes retained')
