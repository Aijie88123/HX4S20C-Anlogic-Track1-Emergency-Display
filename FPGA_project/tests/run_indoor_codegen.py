from pathlib import Path
import tempfile,shutil,subprocess,json,hashlib,sys
R=Path(__file__).resolve().parents[1];E=R/'evidence/follow_view_20261025';P=Path('D:/HX4S20C_building_names_20261025')
Q=Path(tempfile.mkdtemp(prefix='indoor_codegen_'));(Q/'tools').mkdir();(Q/'B_control/rtl').mkdir(parents=True);(Q/'assets').mkdir();shutil.copy2(R/'assets/building_names.json',Q/'assets/building_names.json')
for n in ['generate_indoor_map.py','indoor_renderer_template.v']:shutil.copy2(R/'tools'/n,Q/'tools'/n)
shutil.copy2(P/'B_control/rtl/b_map_frame_renderer_vga.v',Q/'B_control/rtl/b_map_frame_renderer_vga.v')
p=subprocess.run([sys.executable,'-X','utf8',str(Q/'tools/generate_indoor_map.py')],capture_output=True,timeout=60)
assert p.returncode==0,p.stderr.decode(errors='replace')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();files={}
for rel in ['B_control/rtl/emergency_map_top.v','B_control/rtl/b_map_frame_renderer_vga.v',*[str(p.relative_to(Q)).replace('\\','/') for p in (Q/'assets/indoor_map').glob('*')]]:
 assert sha(Q/rel)==sha(R/rel),rel;files[str(R/rel)]=sha(R/rel)
for p in [Path(__file__),R/'tools/generate_indoor_map.py',R/'tools/indoor_renderer_template.v',Path('C:/Windows/Fonts/consola.ttf'),Path('C:/Windows/Fonts/msyh.ttc'),Path('C:/Windows/Fonts/msyhbd.ttc'),R/'assets/building_names.json']:files[str(p)]=sha(p)
(E/'codegen.json').write_text(json.dumps(dict(status='PASS',source_hashes=files,reproduced_files=len(files)-7,scratch_directory=str(Q),native_ROMs=json.loads((R/'assets/indoor_map/scene.json').read_text())['native_map_roms'],original_pipeline_clocks=5,current_pipeline_clocks=5),indent=2))
print('PASS independent regeneration:',len(files)-7,'files; saved',Q)
