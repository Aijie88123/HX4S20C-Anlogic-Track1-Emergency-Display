"""Resolve a named emergency scene to the existing V12 event/control fields."""
from pathlib import Path
import argparse,json
def resolve(name,barrier_mode):
 if barrier_mode not in range(4):raise ValueError('barrier_mode must be 0..3')
 data=json.loads((Path(__file__).resolve().parents[1]/'assets/map_scene_presets.json').read_text(encoding='utf-8'))
 item=next((s for s in data['scenes'] if s['name']==name),None)
 if item is None:raise ValueError('Unknown scene name; expected A, B or C')
 return dict(item,barrier_mode=barrier_mode,actual_state=(item['event_code']<<1)|1)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('name',choices=['A','B','C']);p.add_argument('--barrier-mode',type=int,choices=range(4),default=0);a=p.parse_args()
 print(json.dumps(resolve(a.name,a.barrier_mode),ensure_ascii=False,indent=2))
