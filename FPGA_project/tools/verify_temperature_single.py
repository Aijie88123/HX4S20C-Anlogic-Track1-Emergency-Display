"""Read-only current-source/firmware/report verification; no hardware acceptance claim."""
from pathlib import Path,PureWindowsPath
import hashlib,json,subprocess,sys,re
R=Path(__file__).resolve().parents[1];E=R/'evidence/temperature_single_20261031'
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper();read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
def resolve(n):
 parts=PureWindowsPath(n).parts;i=next((i for i,p in enumerate(parts) if p.startswith('HX4S20C_')),None)
 if i is None:return Path(n) if PureWindowsPath(n).is_absolute() else R/n
 if parts[i].startswith('HX4S20C_ds18b20_module_'):return R.joinpath('evidence/ds18b20_console_20261029/standalone_module',*parts[i+1:])
 return R.joinpath(*parts[i+1:])
def rows(d):
 result=[]
 for k in ['source_hashes','compiled_sources','runner_hashes','support_hashes','generated_hashes']:
  v=d.get(k,{})
  result+=list(v.items()) if isinstance(v,dict) else [(x['path'],x['sha256']) for x in v]
 return result
m=read(E/'production-manifest.json');actual={}
for folder in ['common','assets']+[b+'/'+s for b in ['A_display','B_control'] for s in ['rtl','ip','vendor','constraints','project']]:
 for p in (R/folder).rglob('*'):
  if p.is_file() and 'smart_terminal_Runs' not in p.parts:actual[p.relative_to(R).as_posix()]=h(p)
assert actual==m['current_production_files'] and len(actual)==356
parent=m['parent_production_files'];n='B_control/rtl/temperature_alarm.v'
assert set(parent)==set(actual) and {p for p in parent if parent[p]!=actual[p]}==set(m['changed_existing'])=={n}
assert h(E/'parent_changed_inputs'/n)==parent[n]
for p,v in m['pc_files'].items():assert h(R/p)==v
s=(E/'parent_changed_inputs'/n).read_text(encoding='utf-8-sig')
s=s.replace('module temperature_alarm #(', '// First qualified high-temperature sample latches the alarm.\n// CONFIRM_SAMPLES continues to apply only to cool-down/manual-clear eligibility.\nmodule temperature_alarm #(')
s=s.replace('reg [CCW-1:0] hot_count,cool_count;', 'reg [CCW-1:0] cool_count;').replace('hot_count<=0;','')
s=s.replace('     if(sensor_fault)hot_count<=1;else if(hot_count<CONFIRM_SAMPLES)hot_count<=hot_count+1\'b1;\n','')
s=s.replace('if((sensor_fault?0:hot_count)>=CONFIRM_SAMPLES-1 && !alarm_latched)', 'if(!alarm_latched)').replace('    end else \n','    end\n')
assert (R/n).read_text(encoding='utf-8')==s,'Unexpected change beyond first-hot-sample policy'
selected=read(E/'selected-reports.json');count=0
for rel in selected['new_or_rerun']+selected['exact_unchanged']:
 d=read(R/rel);assert d['status']=='PASS' and rows(d),rel
 for p,v in rows(d):assert resolve(p).is_file() and h(resolve(p))==v.upper(),(rel,p)
 count+=len(rows(d));assert h(R/rel)==selected['report_hashes'][rel]
assert read(E/'policy/result.json')['status']=='PASS'
assert len(read(E/'policy/result.json')['cases'])==2
subprocess.run([sys.executable,'-X','utf8',str(R/'tools/verify_native_resource.py')],check=True)
release=read(E/'release-check.json');assert release['status']=='PASS' and not release['physical_programming_performed'] and not release['HDMI_hardware_test']
assert release['alarm_samples']==1 and release['cool_samples']==3 and release['manual_clear_required'] and release['independent_STOP_required']
for b in ['A_display','B_control']:
 for ext in ['bit','bin']:assert h(R/'firmware'/(b+'_3V3.'+ext))==release['native'][b][ext+'_sha256']
for n,v in release['unchanged_A_firmware'].items():assert h(R/'firmware'/n)==v
assert 'tools/verify_temperature_single.py' in (R/'README.md').read_text(encoding='utf-8')
print(f'PASS:356 production inputs;only B first-valid-hot-sample policy changed/355 exact unchanged. {len(selected["new_or_rerun"])} current/rerun/{len(selected["exact_unchanged"])} exact inherited reports;{count} bound inputs. Current-source B and exact-parent A timing/fourDRC/firmware verified. No new board programming or HDMI/temperature hardware acceptance.')
