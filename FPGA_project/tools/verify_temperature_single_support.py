from pathlib import Path,PureWindowsPath
R=Path(__file__).resolve().parents[1]
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
