from pathlib import Path
import hashlib,json
R=Path(__file__).resolve().parents[1];P=Path('D:/HX4S20C_flip_zoom_20261024');F=Path('D:/HX4S20C_scan_trace_20261024');O=R/'evidence/map_abc_20261025';O.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
dirs=['A_display/rtl','B_control/rtl','common','A_display/constraints','B_control/constraints','A_display/ip','B_control/ip','A_display/vendor','B_control/vendor','A_display/project','B_control/project'];ext={'.v','.vh','.sv','.svh','.adc','.sdc','.tcl','.cfg','.prj','.mem','.hex','.mif','.ps1','.ipc','.xml'}
def inv(root):return {p.relative_to(root).as_posix():sha(p) for d in dirs for p in (root/d).rglob('*') if p.is_file() and 'smart_terminal_Runs' not in p.parts and p.suffix.lower() in ext}
a,b,f=inv(P),inv(R),inv(F);assert a.keys()==b.keys()==f.keys();assert b==f,'Parameter aliases must not change working hardware inputs'
changed=sorted(k for k in a if a[k]!=b[k]);assert set(changed)=={'A_display/rtl/smart_terminal_hw_top.v','A_display/vendor/user_source/hdl_source/include/sdr_init_ref.enc.v','A_display/project/phy_settings.cfg'},changed
sources={str(R/k):v for k,v in b.items()}
for rel in ['assets/map_scene_presets.json','assets/map_scene_parameters.json','tools/generate_map_scene_parameters.py','tools/resolve_map_scene.py']:sources[str(R/rel)]=sha(R/rel)
for board in ['A_display','B_control']:
 m=json.loads((F/board/'evidence/map_detail_20261020/build-manifest.json').read_text(encoding='utf-8-sig'))
 for row in m['sources']:assert sha(R/board/row['path'])==row['sha256'].upper(),(board,row['path'])
 for extn in ['bit','bin']:assert sha(R/'firmware'/f'{board}_3V3.{extn}')==sha(F/'firmware'/f'{board}_3V3.{extn}')
report=dict(status='PASS',parent=str(P),working_firmware_reference=str(F),production_changes=changed,production_changes_vs_working_firmware=[],parent_production_hashes=a,current_production_hashes=b,source_hashes=sources,runner_hashes={str(Path(__file__).resolve()):sha(Path(__file__))},scope='Only named-scene parameter data/API/generation/tests are new. Names resolve before existing canonical event/live-barrier controls. All production inputs and four bit/bin files byte-identical to working scan_trace; steady white-line fixes, F/E diagnostics, transitions, B/common/TF/network/audio/clocks/pins/SDC retained. No new hardware build or firmware update required.')
(O/'scope.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');(O/'production.diff').write_text('No production changes relative to current working scan_trace. Three inherited repair/diagnostic/seed differences relative to unique flip_zoom are enumerated in scope.json. New files implement parameter aliases only.\n',encoding='utf-8')
print('PASS: parameter layer only; all production inputs/firmware identical to working scan_trace')
