"""Validate and export named scene parameters before canonical FPGA controls."""
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1]
d=json.loads((R/'assets/map_scene_presets.json').read_text(encoding='utf-8'))
assert d['schema_version']==1 and [s['name'] for s in d['scenes']]==['A','B','C']
assert [s['event_code'] for s in d['scenes']]==[0,1,2]
for s in d['scenes']:
 assert s['exit_policy']=='automatic_shortest_reachable'
 assert s['allowed_exit_nodes']==[9,10,11,12]
 assert s['barrier_policy']=='live_existing_control'
assert d['legacy_event']['event_code']==3 and d['legacy_event']['named_alias'] is None
resolved={s['name']:dict(s,actual_state=(s['event_code']<<1)|1) for s in d['scenes']}
text=json.dumps(dict(schema_version=1,control_interface='existing V12 actual_state and live barrier_mode',scenes=resolved,legacy_event=d['legacy_event']),ensure_ascii=False,indent=2)+'\n'
p=R/'assets/map_scene_parameters.json'
if '--check' in sys.argv:assert p.read_text(encoding='utf-8')==text,'Generated scene parameters stale'
else:p.write_text(text,encoding='utf-8')
print('PASS: A/B/C canonical event parameters exported; automatic exits/live barriers; no RTL change')
