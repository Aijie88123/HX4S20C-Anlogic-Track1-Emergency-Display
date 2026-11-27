"""Read-only verification; selected current-source evidence only."""
from pathlib import Path,PureWindowsPath
import json,hashlib,re,subprocess,sys
R=Path(__file__).resolve().parents[1];E=R/'evidence/temperature_osd_20261030'
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
def resolve(n):
 parts=PureWindowsPath(n).parts;i=next((i for i,p in enumerate(parts) if p.startswith('HX4S20C_')),None)
 if i is None:return Path(n) if PureWindowsPath(n).is_absolute() else R/n
 if parts[i].startswith('HX4S20C_ds18b20_module_'):return R.joinpath('evidence/ds18b20_console_20261029/standalone_module',*parts[i+1:])
 return R.joinpath(*parts[i+1:])
def bound_rows(d):
 rows=[]
 for key in ['source_hashes','compiled_sources','runner_hashes','support_hashes','generated_hashes']:
  v=d.get(key,{})
  rows+=list(v.items()) if isinstance(v,dict) else [(x['path'],x['sha256']) for x in v]
 return rows
m=read(E/'production-manifest.json');actual={}
for folder in ['common','assets']+[b+'/'+s for b in ['A_display','B_control'] for s in ['rtl','ip','vendor','constraints','project']]:
 for p in (R/folder).rglob('*'):
  if p.is_file() and 'smart_terminal_Runs' not in p.parts:actual[p.relative_to(R).as_posix()]=h(p)
assert actual==m['current_production_files'] and len(actual)==356
parent=m['parent_production_files'];changed={n for n in parent if actual[n]!=parent[n]}
assert set(actual)==set(parent) and changed==set(m['changed_existing']) and len(changed)==5
for n in changed:assert h(E/'parent_changed_inputs'/n)==parent[n]
for n,v in m['pc_files'].items():assert h(R/n)==v
for b in ['A_display','B_control']:
 for name in ['pin.adc','timing.sdc']:
  p=b+'/constraints/'+name;assert actual[p]==parent[p]
for n in ['onewire_slot.v','ds18b20_master.v','temperature_alarm.v','ds18b20_emergency.v']:
 assert actual['B_control/rtl/'+n]==parent['B_control/rtl/'+n]
for n in ['common/dual_board_emergency_control.v','A_display/rtl/dual_board_emergency_control.v','B_control/rtl/dual_board_emergency_control.v']:
 assert actual[n]==parent[n]
selected=read(E/'selected-reports.json');count=0
for rel in selected['new_or_rerun']+selected['exact_unchanged']:
 d=read(R/rel);assert d['status']=='PASS',rel;rows=bound_rows(d);assert rows,rel
 for name,v in rows:
  p=resolve(name);assert p.is_file() and h(p)==v.upper(),(rel,name)
 count+=len(rows)
for rel,v in selected['inherited_report_hashes'].items():assert h(R/rel)==v
assert len(read(E/'simulation/result.json')['observations'])>0
text=(R/'A_display/rtl/text_overlay_8x8.v').read_text(encoding='utf-8')
inits=lambda s:{int(n,16):int(v,16) for n,v in re.findall(r"\.INIT_([0-9A-Fa-f]{2})\(256'h([0-9A-Fa-f]{64})\)",s)}
font=inits(text);reference=inits((E/'compositor_reference.v').read_text(encoding='utf-8'))
assert all(font[n]==reference[n] for n in range(64)), 'Original font contents changed'
for value in range(128):
 assert (font[64+value//16]>>(16*(value%16)))&65535==((value%100)//10)*16+value%10
assert 'ENABLE_INTEGER_LOOKUP(ENABLE_TEMPERATURE_OSD)' in text
for symbol in ['second_cycle_cnt','elapsed_bcd','displayed_bcd','date_char','time_char','time_hit']:
 assert symbol not in text,'Removed display clock logic reappeared: '+symbol
overlay=(R/'A_display/rtl/smart_terminal_overlay_pipelined.v').read_text(encoding='utf-8')
assert 'second_divider' not in overlay and not re.search(r'reg.*elapsed_seconds',overlay)
subprocess.run([sys.executable,'-X','utf8',str(R/'tools/verify_native_resource.py')],check=True)
release=read(E/'release-check.json');assert release['status']=='PASS' and not release['physical_programming_performed']
for b in ['A_display','B_control']:
 for ext in ['bit','bin']:assert h(R/'firmware'/(b+'_3V3.'+ext))==release['native'][b][ext+'_sha256']
assert '配套' in (R/'README.md').read_text(encoding='utf-8')
assert 'tools/verify_temperature_osd.py' in (R/'README.md').read_text(encoding='utf-8')
print(f'PASS:356 production inputs;5 changed/351 exact unchanged; display date/time logic removed and replaced by temperature; waveform coordinate register relocation independently cycle-exact. A/B original ADC+SDC and acquisition/alarm/ownership/PC unchanged. {len(selected["new_or_rerun"])} current/rerun and {len(selected["exact_unchanged"])} exact unchanged reports;{count} bound inputs. Both current-source native setup/hold/fourDRC/firmware verified. New HDMI HUD not physically accepted.')
