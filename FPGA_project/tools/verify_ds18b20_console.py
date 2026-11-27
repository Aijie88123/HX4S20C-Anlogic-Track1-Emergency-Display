"""Read-only verification of current integrated source, native signoff and reports."""
from pathlib import Path,PureWindowsPath
import json,hashlib,subprocess,sys,re
R=Path(__file__).resolve().parents[1];E=R/'evidence/ds18b20_console_20261029'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
def resolve(n):
 parts=PureWindowsPath(n).parts;i=next((i for i,v in enumerate(parts) if v.startswith('HX4S20C_')),None)
 if i is None:return Path(n) if PureWindowsPath(n).is_absolute() else R/n
 if parts[i].startswith('HX4S20C_ds18b20_module_'):return E.joinpath('standalone_module',*parts[i+1:])
 return R.joinpath(*parts[i+1:])
def reports(rels):
 count=0
 for rel in rels:
  d=read(R/rel);assert d['status']=='PASS',rel;rows=[]
  for k in ['source_hashes','compiled_sources','runner_hashes','support_hashes','generated_hashes']:
   h=d.get(k,{});rows+=list(h.items()) if isinstance(h,dict) else [(v['path'],v['sha256']) for v in h]
  assert rows,rel
  for n,h in rows:assert resolve(n).is_file() and sha(resolve(n))==h.upper(),(rel,n)
  count+=len(rows)
 return count
m=read(E/'production-manifest.json');actual={}
for folder in ['common','assets']+[b+'/'+s for b in ['A_display','B_control'] for s in ['rtl','ip','vendor','constraints','project']]:
 for p in (R/folder).rglob('*'):
  if p.is_file() and 'smart_terminal_Runs' not in p.parts:actual[p.relative_to(R).as_posix()]=sha(p)
assert actual==m['current_production_files'],'Unexpected production change'
parent=m['parent_production_files'];changed={n for n in parent if actual[n]!=parent[n]};added=set(actual)-set(parent)
assert len(parent)==352 and len(actual)==356 and not (set(parent)-set(actual))
assert changed==set(m['changed_existing']) and added==set(m['added_inputs']) and len(changed)==11 and len(added)==4
for n in changed:assert sha(E/'parent_changed_inputs'/n)==parent[n]
for n in ['onewire_slot.v','ds18b20_master.v','temperature_alarm.v','ds18b20_emergency.v']:
 assert sha(R/'B_control/rtl'/n)==sha(E/'standalone_module/rtl'/n)
for n in ['pin.adc','timing.sdc']:
 p=R/'B_control/constraints'/n;old=(E/'parent_changed_inputs/B_control/constraints'/n).read_bytes();assert p.read_bytes().startswith(old)
 tail=p.read_bytes()[len(old):].decode();assert 'ds18b20_dq' in tail
 if n=='pin.adc':assert 'N12' in tail and 'LVCMOS33' in tail and re.search(r'PULLTYPE\s*=\s*NONE',tail)
 else:assert tail.count('set_false_path')==1 and 'set_clock' not in tail
owners=[R/p/'dual_board_emergency_control.v' for p in ['A_display/rtl','B_control/rtl','common']]
assert len({sha(p) for p in owners})==1
assert 'remote_command[0] && !local_owned' in owners[0].read_text() and 'wire remote_owner=emergency_mode && !local_owned;' in owners[0].read_text()
top=(R/'B_control/rtl/dual_board_control_top.v').read_text()
assert '.PERIOD0_MS(3000),.PERIOD1_MS(5000),.PERIOD2_MS(FAST_DEMO?8000:10000)' in top
assert 'T03S' in (R/'README.md').read_text(encoding='utf-8')
sel=read(E/'selected-reports.json');count=reports(sel['new_or_rerun']+sel['exact_unchanged'])
subprocess.run([sys.executable,'-X','utf8',str(E/'standalone_module/tools/verify_module.py')],check=True)
subprocess.run([sys.executable,'-X','utf8',str(R/'tools/verify_native_resource.py')],check=True)
release=read(E/'release-check.json');assert release['status']=='PASS' and release['physical_test'] is False
for board in ['A_display','B_control']:
 for ext in ['bit','bin']:assert sha(R/'firmware'/(board+'_3V3.'+ext))==release['native'][board][ext+'_sha256']
 io=(R/board/'evidence/map_detail_20261020/smart_terminal_phy.area').read_text()
 if board=='B_control':assert 'ds18b20_dq' in io and 'N12' in io
print(f'PASS:356 production inputs;11 changed existing +4 exact standalone sensor RTL;341 exact unchanged. {len(sel["new_or_rerun"])} current/rerun +{len(sel["exact_unchanged"])} exact unchanged reports/{count} bound input hashes. Paired current-source native setup/hold/fourDRC/firmware verified; no physical acceptance claimed.')
