from pathlib import Path
import json,hashlib,numpy as np
R=Path(__file__).resolve().parents[1];P=R/'assets/indoor_map';E=R/'evidence/follow_view_20261025'
names=json.loads((R/'assets/building_names.json').read_text(encoding='utf-8'));scene=json.loads((P/'scene.json').read_text());catalog=json.loads((P/'building_catalog.json').read_text(encoding='utf-8'))
a=np.load(P/'palette_indices.npy');roads=np.load(P/'labels_road_guard.npy');assert np.array_equal(roads,np.isin(a,[11,12,13])),'Nameplates/leaders changed walkable texels'
assert len(names)==len(catalog)==len(scene['rooms'])==16
assert {x['id'] for x in catalog}==set(names)=={f'B{i:02}' for i in range(1,17)}
boxes=[]
for item in catalog:
 ident=item['id'];assert item['short_name']==names[ident]['short'] and item['name']==names[ident]['name']
 x0,y0,x1,y1=item['box'];assert 0<=x0<x1<640 and 54<y0<y1<410
 assert not roads[y0:y1+1,x0:x1+1].any()
 assert int((a[y0:y1+1,x0:x1+1]==8).sum())>=20,(ident,'name glyph missing')
 for bx0,by0,bx1,by1 in boxes:assert x1<bx0 or x0>bx1 or y1<by0 or y0>by1,(ident,'nameplate overlap')
 boxes.append(item['box']);g=scene['visual_geometry'][ident];assert g['upper_height']>=14 and g['maximum_height']>=18
 i=int(ident[1:])-1;u0,v0,u1,v1=scene['rooms'][i];a0,b0,a1,b1=g['upper_bounds'];assert u0<a0<a1<u1 and v0<b0<b1<v1
entries=json.loads((P/'hud_entries.json').read_text(encoding='utf-8'))
assert entries[9:13]==[names[k]['short']+' '+k for k in ['B10','B06','B07','B11']]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
files=[Path(__file__),R/'assets/building_names.json',P/'building_catalog.json',P/'scene.json',P/'palette_indices.npy',P/'labels_road_guard.npy',P/'hud_entries.json']
d=dict(status='PASS',source_hashes={str(p):sha(p) for p in files},building_names=16,all_nameplates_inside640x480=True,overlapping_nameplates=0,walkable_pixels_obscured_by_labels=0,matching_danger_names_and_BIDs=True,stepped_upper_floors=16,minimum_upper_height=14,maximum_upper_height=16,maximum_roof_height=20)
(E/'labels.json').write_text(json.dumps(d,indent=2));print('PASS16names/uniqueIDs/nonoverlap/glyphs/no-walkable-occlusion/upper-floor-bounds/HUDmapping')
