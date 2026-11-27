from pathlib import Path
import hashlib,json
R=Path(__file__).resolve().parents[1];E=R/'evidence/follow_view_20261025';parent=json.loads((E/'parent-inputs.json').read_text());P=Path(parent['parent'])
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
diff=[]
for rel,dig in parent['files'].items():
 assert sha(P/rel)==dig,'Parent was modified: '+rel
 if sha(R/rel)!=dig:diff.append(rel)
assert diff==['B_control/rtl/emergency_map_top.v'],diff
assert (R/'B_control/rtl/b_map_frame_renderer_vga.v').read_bytes()==(P/'B_control/rtl/b_map_frame_renderer_vga.v').read_bytes()
scene=json.loads((R/'assets/indoor_map/scene.json').read_text())
previous_scene=json.loads((P/'assets/indoor_map/scene.json').read_text())
assert scene['rooms']==previous_scene['rooms'] and len(scene['rooms'])==16
assert scene['projection']==previous_scene['projection']
old=(P/'B_control/rtl/emergency_map_top.v').read_text();new=(R/'B_control/rtl/emergency_map_top.v').read_text()
assert old[old.index('module emergency_map_top #('):old.index('reg [4:0] flow;')]==new[new.index('module emergency_map_top #('):new.index('reg [4:0] flow;')]
restored=new
a=restored.index('// Restore the original A smooth camera')
b=restored.index('wire [14:0] tile_address=')
restored=restored[:a]+old[old.index('// Zoom retains'):old.index('wire [14:0] tile_address=')]+restored[b:]
restored=restored.replace('screen_band1,screen_band2,map_content1,map_content2','screen_band1,screen_band2')
restored=restored.replace(' map_content1<=map_content;map_content2<=map_content1;\n','')
restored=restored.replace('valid1<=active&&remote_live&&ix<640&&iy<480;','valid1<=active&&remote_live&&vx<640&&vy<480;')
restored=restored.replace('&&map_content2','')
assert restored==old,'unexpected production change beyond camera/boundary gates'
for asset in ['palette_indices.npy','hud_bits.npy','index.hex','atlas.hex','hud.hex','building_catalog.json','scene.json']:
 assert sha(R/'assets/indoor_map'/asset)==sha(P/'assets/indoor_map'/asset),asset
assert sha(R/'assets/building_names.json')==sha(P/'assets/building_names.json')

for token in ['wire signed [12:0] world_v=',' u2<=','wire signed [13:0] gu=','wire signed [13:0] gv=','wire signed [13:0] gx=']:
 assert next(x for x in old.splitlines() if x.startswith(token))==next(x for x in new.splitlines() if x.startswith(token)),token
nodes=[(80+176*(i%3),80+176*(i//3)) for i in range(9)]+[(256,0),(0,256),(512,256),(256,512)]
edges=[(0,1),(1,2),(3,4),(4,5),(6,7),(7,8),(0,3),(3,6),(1,4),(4,7),(2,5),(5,8),(1,9),(3,10),(5,11),(7,12)]
checked=0
for k,(a,b) in enumerate(edges):
 ua,va=nodes[a];ub,vb=nodes[b];length=abs(ua-ub)+abs(va-vb);assert length==(176 if k<12 else 80)
 for step in range(length+1):
  u=ua+(ub-ua)*step/length;v=va+(vb-va)*step/length
  for u0,v0,u1,v1 in scene['rooms']:assert not (u0-10<=u<=u1+10 and v0-10<=v<=v1+10),(k,step,'route/room collision')
  checked+=1
files={str(R/rel):sha(R/rel) for rel in parent['files']}
for p in [Path(__file__),R/'tools/generate_indoor_map.py',R/'tools/indoor_renderer_template.v',R/'assets/indoor_map/scene.json',E/'parent-inputs.json']:files[str(p)]=sha(p)
out=dict(status='PASS',source_hashes=files,production_changes=diff,A_identical=True,frame_lifecycle_mechanical_equivalence=True,route_geometry_samples=checked,graph_weights_and_topology_unchanged=True,building_count=16,building_footprints_and_projection_unchanged=True,module_interface_and_route_edge_decoder_unchanged=True,original_hazard_node_region_unchanged=True,camera_sampling_and_boundary_gates_only=True,art_and_names_byte_identical=True,TF_SDRAM_FIFO_V12_clocks_constraints_pins_unchanged=True)
(E/'scope.json').write_text(json.dumps(out,indent=2));print('PASS: exactly1BRTL; allA/transport/memory/audio/constraints unchanged; corridor graph points',checked)
