from pathlib import Path,PureWindowsPath
import json,hashlib,subprocess,sys
R=Path(__file__).resolve().parents[1];E=R/'evidence/uart_subtitle_fixed_20261026';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper();read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
e=read(E/'production-equivalence.json');expected={}
for name,h in e['source_hashes'].items():
 parts=PureWindowsPath(name).parts;i=next(i for i,p in enumerate(parts) if p.startswith('HX4S20C_'));rel=Path(*parts[i+1:]).as_posix();expected[rel]=h.upper();assert sha(R/rel)==h.upper(),rel
actual={}
for rel in ['common','assets']+[b+'/'+s for b in ['A_display','B_control'] for s in ['rtl','ip','vendor','constraints','project']]:
 for p in (R/rel).rglob('*'):
  if p.is_file() and 'smart_terminal_Runs' not in p.parts:actual[p.relative_to(R).as_posix()]=sha(p)
assert expected==actual
for rel,h in e['firmware_hashes'].items():assert sha(R/rel)==h
assert read(E/'gui/result.json')['source_sha256'].upper()==sha(R/'tools/subtitle_sender.ps1')
for name in ['verify_subtitle_reports.py','verify_native_resource.py']:subprocess.run([sys.executable,'-X','utf8',str(R/'tools'/name)],check=True)
print(f'PASS: repaired tool + {len(expected)} unchanged production inputs + four exact parent firmware files; no new synthesis or hardware acceptance claimed')
