from pathlib import Path
import numpy as np,json,hashlib
R=Path(__file__).resolve().parents[1];a=np.load(R/'assets/indoor_map/palette_indices.npy');y,x=np.indices(a.shape);u=x-320+2*(y-94);v=2*(y-94)-(x-320)
nodes=[(80+176*(i%3),80+176*(i//3)) for i in range(9)]+[(256,0),(0,256),(512,256),(256,512)]
edges=[(0,1),(1,2),(3,4),(4,5),(6,7),(7,8),(0,3),(3,6),(1,4),(4,7),(2,5),(5,8),(1,9),(3,10),(5,11),(7,12)]
rows=[]
for k,(i,j) in enumerate(edges):
 ua,va=nodes[i];ub,vb=nodes[j];mask=(abs(v-va)<=10)&(u>=min(ua,ub))&(u<=max(ua,ub)) if va==vb else (abs(u-ua)<=10)&(v>=min(va,vb))&(v<=max(va,vb))
 total=int(mask.sum());visible=int((mask&np.isin(a,[11,12,13])).sum());rows.append(dict(edge=k,projected_pixels=total,visible_road_pixels=visible,ratio=round(visible/total,4)))
 assert visible>0,(k,'entire corridor occluded')
# Same demonstration path edge4+exit15. A visibility metric, not a reachability test.
mask=((abs(v-432)<=10)&(u>=80)&(u<=256))|((abs(u-256)<=10)&(v>432)&(v<=512))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
d=dict(status='PASS',source_hashes={str(p):sha(p) for p in [Path(__file__),R/'assets/indoor_map/palette_indices.npy',R/'tools/generate_indoor_map.py']},edges=rows,demo_projected_pixels=int(mask.sum()),demo_visible_pixels=int((mask&np.isin(a,[11,12,13])).sum()),limits='Visibility is a raster architectural occlusion metric, not hardware FPS or an independent solver proof.')
(R/'evidence/follow_view_20261025/visibility.json').write_text(json.dumps(d,indent=2));print(json.dumps(d['edges'],indent=2));print('demo visible',d['demo_visible_pixels'],'of',d['demo_projected_pixels'])
