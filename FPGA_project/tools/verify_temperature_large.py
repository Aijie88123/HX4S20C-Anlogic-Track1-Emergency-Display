"""Read-only verification of the font-only candidate and signed firmware."""
from pathlib import Path,PureWindowsPath
import hashlib,json,subprocess,sys,re
R=Path(__file__).resolve().parents[1];E=R/'evidence/temperature_large_20261031'
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
parent=m['parent_production_files'];n='A_display/rtl/text_overlay_8x8.v'
assert set(parent)==set(actual) and {p for p in parent if parent[p]!=actual[p]}==set(m['changed_existing'])=={n}
assert h(E/'parent_changed_inputs'/n)==parent[n]
for p,v in m['pc_files'].items():assert h(R/p)==v
s=(E/'parent_changed_inputs'/n).read_text(encoding='utf-8-sig')
for a,b in [('y_pre<TEMP_Y+8','y_pre<TEMP_Y+16'),('temperature_rx_pre[6:3]','temperature_rx_pre[7:4]'),('temperature_ry_pre[2:0],temperature_rx_pre[2:0]','temperature_ry_pre[3:1],temperature_rx_pre[3:1]'),('TEMP_CHARS*8','TEMP_CHARS*16'),('y_pre<TEMP_Y+12','y_pre<TEMP_Y+20')]:s=s.replace(a,b)
s=s.replace('wire [11:0] temperature_rx_pre=x_pre-TEMP_X;', '// Temperature alone uses 2x nearest-neighbour glyph expansion (16x16).\n    wire [11:0] temperature_rx_pre=x_pre-TEMP_X;')
assert (R/n).read_text(encoding='utf-8')==s,'Unexpected source change beyond temperature geometry'
selected=read(E/'selected-reports.json');count=0
for rel in selected['new_or_rerun']+selected['exact_unchanged']:
 d=read(R/rel);assert d['status']=='PASS' and rows(d),rel
 for p,v in rows(d):assert resolve(p).is_file() and h(resolve(p))==v.upper(),(rel,p)
 count+=len(rows(d));assert h(R/rel)==selected['report_hashes'][rel]
for name in ['simulation','pipeline']:assert read(E/name/'result.json')['status']=='PASS'
subprocess.run([sys.executable,'-X','utf8',str(R/'tools/verify_native_resource.py')],check=True)
release=read(E/'release-check.json');assert release['status']=='PASS' and not release['physical_programming_performed'] and not release['HDMI_hardware_test']
assert release['temperature_geometry']==dict(x=24,y=18,cell_width=16,cell_height=16,chars=16,width=256,height=16,background=[20,16,284,38])
for b in ['A_display','B_control']:
 for ext in ['bit','bin']:assert h(R/'firmware'/(b+'_3V3.'+ext))==release['native'][b][ext+'_sha256']
for n,v in release['unchanged_B_firmware'].items():assert h(R/'firmware'/n)==v
assert 'tools/verify_temperature_large.py' in (R/'README.md').read_text(encoding='utf-8')
print(f'PASS:356 production inputs;only A temperature text geometry changed/355 exact unchanged;8x8->16x16 at x24/y18. {len(selected["new_or_rerun"])} current/rerun/{len(selected["exact_unchanged"])} exact inherited reports;{count} bound inputs. Current-source A and exact-parent B timing/fourDRC/firmware verified. No new board programming or HDMI hardware acceptance.')
