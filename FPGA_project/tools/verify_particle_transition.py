"""Read-only release verification, including current-source physical evidence."""
from pathlib import Path,PureWindowsPath
import hashlib,json,subprocess,sys
R=Path(__file__).resolve().parents[1];E=R/'evidence/particle_transition_20261031'
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
def resolve(n):
 parts=PureWindowsPath(n).parts;i=next((i for i,p in enumerate(parts) if p.startswith('HX4S20C_')),None)
 if i is None:return Path(n) if PureWindowsPath(n).is_absolute() else R/n
 if parts[i].startswith('HX4S20C_ds18b20_module_'):return R.joinpath('evidence/ds18b20_console_20261029/standalone_module',*parts[i+1:])
 return R.joinpath(*parts[i+1:])
def rows(d):
 out=[]
 for k in ['source_hashes','compiled_sources','runner_hashes','support_hashes','generated_hashes']:
  v=d.get(k,{})
  out+=list(v.items()) if isinstance(v,dict) else [(x['path'],x['sha256']) for x in v]
 return out
m=read(E/'production-manifest.json');actual={}
for folder in ['common','assets']+[b+'/'+s for b in ['A_display','B_control'] for s in ['rtl','ip','vendor','constraints','project']]:
 for p in (R/folder).rglob('*'):
  if p.is_file() and 'smart_terminal_Runs' not in p.parts:actual[p.relative_to(R).as_posix()]=h(p)
assert actual==m['current_production_files'] and len(actual)==356
parent=m['parent_production_files'];changed={n for n in parent if parent[n]!=actual[n]}
assert set(parent)==set(actual) and changed==set(m['changed_existing'])=={'A_display/rtl/'+n for n in ['smart_terminal_hw_top.v','video_scanout_720p.v','distributed_media.v','map_received_scanout.v']}
for n in changed:assert h(E/'parent_changed_inputs'/n)==parent[n]
for n,v in m['pc_files'].items():assert h(R/n)==v
assert all(actual[n]==parent[n] for n in actual if n.startswith(('B_control/','common/')) or '/constraints/' in n)
for n in ['text_overlay_8x8.v','smart_terminal_overlay_pipelined.v','audio_waveform_precise_overlay.v','a_media_cached_control.v','dual_board_emergency_control.v']:
 assert actual['A_display/rtl/'+n]==parent['A_display/rtl/'+n]
selected=read(E/'selected-reports.json');count=0
for rel in selected['new_or_rerun']+selected['exact_unchanged']:
 d=read(R/rel);assert d['status']=='PASS' and rows(d),rel
 for name,v in rows(d):
  p=resolve(name);assert p.is_file() and h(p)==v.upper(),(rel,name)
 count+=len(rows(d))
 assert h(R/rel)==selected['report_hashes'][rel]
for n in ['simulation','manual','native_memory']:assert read(E/n/'result.json')['observations']
top=(R/'A_display/rtl/smart_terminal_hw_top.v').read_text(encoding='utf-8-sig')
assert '.HOLD_COMPLETE_FRAME(1)' in top and '.RGB444_SUPPORT(1)' in top and '.GEOMETRY_RGB444(ENABLE_MEDIA)' in top and '.DYNAMIC_SLOTS(1)' in top
assert 'photo_geometry_active || (map_mode && !normal_animation_ready_video[1])' in top
assert 'else if(res_tgl_sync[2] ^ res_tgl_sync[1])geometry_committed_photo<=display_slot;' in top
text=(R/'A_display/rtl/text_overlay_8x8.v').read_text(encoding='utf-8-sig');assert 'second_cycle_cnt' not in text and 'time_char' not in text
subprocess.run([sys.executable,'-X','utf8',str(R/'tools/verify_native_resource.py')],check=True)
release=read(E/'release-check.json');assert release['status']=='PASS' and not release['physical_programming_performed'] and not release['HDMI_hardware_test']
for b in ['A_display','B_control']:
 for ext in ['bit','bin']:assert h(R/'firmware'/(b+'_3V3.'+ext))==release['native'][b][ext+'_sha256']
for n,v in release['unchanged_B_firmware'].items():assert h(R/'firmware'/n)==v
assert 'tools/verify_particle_transition.py' in (R/'README.md').read_text(encoding='utf-8')
print(f'PASS:356 production inputs;4 A-only changes/352 exact unchanged; B/common/ADC/SDC/sensor/temperature UI/PC and scheduling exact parent. {len(selected["new_or_rerun"])} current/rerun, {len(selected["exact_unchanged"])} exact inherited reports;{count} bound inputs. Selected A current-source and B exact-source original-SDC setup/hold/fourDRC/firmware verified. New HDMI behavior not hardware-accepted.')
