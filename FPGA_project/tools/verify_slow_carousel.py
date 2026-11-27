from pathlib import Path,PureWindowsPath
import hashlib,json,subprocess,sys
R=Path(__file__).resolve().parents[1];E=R/'evidence/slow_carousel_20261029'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
def resolve(n):
 parts=PureWindowsPath(n).parts;i=next((i for i,v in enumerate(parts) if v.startswith('HX4S20C_')),None)
 return R.joinpath(*parts[i+1:]) if i is not None else (Path(n) if PureWindowsPath(n).is_absolute() else R/n)
def check_reports(reports):
 count=0
 for rel in reports:
  d=read(R/rel);assert d['status']=='PASS',rel;rows=[]
  for k in ['source_hashes','compiled_sources','runner_hashes','support_hashes','generated_hashes']:
   h=d.get(k,{});rows+=list(h.items()) if isinstance(h,dict) else [(v['path'],v['sha256']) for v in h]
  assert rows,rel
  for n,h in rows:assert resolve(n).is_file() and sha(resolve(n))==h.upper(),(rel,n)
  count+=len(rows)
 return count
manifest=read(E/'production-manifest.json');actual={}
for folder in ['common','assets']+[b+'/'+s for b in ['A_display','B_control'] for s in ['rtl','ip','vendor','constraints','project']]:
 for p in (R/folder).rglob('*'):
  if p.is_file() and 'smart_terminal_Runs' not in p.parts:actual[p.relative_to(R).as_posix()]=sha(p)
assert actual==manifest['current_production_files'],'Unexpected production change'
changes=read(E/'production-diff.json')['production_changes']
restores={
 'B_control/rtl/dual_board_control_top.v':[(b'.PERIOD0_MS(3000),.PERIOD1_MS(5000),.PERIOD2_MS(FAST_DEMO?8000:10000)',b'.PERIOD0_MS(FAST_DEMO?350:3000),.PERIOD1_MS(FAST_DEMO?1000:5000),.PERIOD2_MS(FAST_DEMO?2000:10000)')],
 'A_display/rtl/smart_terminal_hw_top.v':[(b'.NORMAL_PERIOD_MS(3000)',b'.NORMAL_PERIOD_MS(FAST_DEMO?350:3000)')],
 'A_display/rtl/text_overlay_8x8.v':[(b'DEMO_FAST_PERIODS ? "0"',b'DEMO_FAST_PERIODS ? (interval_selection==0 ? "M" : "0")'),(b'DEMO_FAST_PERIODS ? (interval_selection==0 ? "3" : interval_selection==1 ? "5" : "8")',b'DEMO_FAST_PERIODS ? (interval_selection==0 ? "A" : interval_selection==1 ? "1" : "2")'),(b'3: period_char="S";',b'3: period_char=DEMO_FAST_PERIODS && interval_selection==0 ? "X" : "S";')]}
assert len(actual)==352 and len(changes)==3
for row in changes:
 data=(R/row['path']).read_bytes();assert sha(R/row['path'])==row['sha256']
 for old,new in restores[row['path']]:
  assert data.count(old)==1,(row['path'],old)
  data=data.replace(old,new)
 assert hashlib.sha256(data).hexdigest().upper()==row['parent_sha256'],row['path']
sel=read(E/'selected-reports.json');count=check_reports(sel['new_or_rerun']+sel['exact_unchanged'])
subprocess.run([sys.executable,'-X','utf8',str(R/'tools/verify_native_resource.py')],check=True)
release=read(E/'release-check.json');assert release['status']=='PASS' and release['physical_test'] is False
for board in ['A_display','B_control']:
 for ext in ['bit','bin']:
  p=R/'firmware'/(board+'_3V3.'+ext)
  assert sha(p)==release['native'][board][ext+'_sha256']
print(f'PASS: 352 production inputs; exactly3 files restored byte-for-byte to parent;349 unchanged; '+str(len(sel['new_or_rerun']))+' new/rerun and '+str(len(sel['exact_unchanged']))+' exact unchanged reports; '+str(count)+' report input hashes; both current-source native original-constraint setup/hold/fourDRC/bitgen verified. No hardware acceptance claimed.')
