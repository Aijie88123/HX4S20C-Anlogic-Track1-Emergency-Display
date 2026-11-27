"""Validate selected reports against this checkout, including extracted releases."""
from pathlib import Path,PureWindowsPath
import json,hashlib
R=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
def resolve(name):
 parts=PureWindowsPath(name).parts;i=next((i for i,n in enumerate(parts) if n.startswith('HX4S20C_')),None)
 return R.joinpath(*parts[i+1:]) if i is not None else (Path(name) if PureWindowsPath(name).is_absolute() else R.joinpath(*parts))
reports=json.loads((R/'evidence/uart_service_20261026/selected-tests.json').read_text());count=0
for rel in reports:
 d=json.loads((R/rel).read_text(encoding='utf-8-sig'));assert d['status']=='PASS',rel;rows=[]
 for k in ['source_hashes','compiled_sources','runner_hashes','support_hashes','generated_hashes']:
  h=d.get(k,{});rows+=list(h.items()) if isinstance(h,dict) else [(v['path'],v['sha256']) for v in h]
 assert rows,rel
 for name,digest in rows:
  p=resolve(name);assert p.exists() and sha(p)==digest.upper(),(rel,name)
 count+=len(rows)
print(f'PASS: {len(reports)} selected reports, {count} recorded input hashes; no hardware validation claimed')
