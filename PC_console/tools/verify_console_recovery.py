from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest().upper()
count=0
for line in (root/'SHA256SUMS.txt').read_text(encoding='utf-8-sig').splitlines():
    digest,name=line.split('  ',1)
    target=(root/name).resolve()
    assert target.is_relative_to(root) and target.is_file(),name
    assert sha(target)==digest,name
    count+=1
assert json.loads((root/'evidence/recovery/result.json').read_text(encoding='utf-8-sig'))['status']=='PASS'
assert json.loads((root/'evidence/recovery/physical-readonly.json').read_text(encoding='utf-8-sig'))['success']
assert json.loads((root/'evidence/recovery/physical-repair.json').read_text(encoding='utf-8-sig'))['success']
for name in ['original-core.log','original-gui.log','original-sensor.log','recovery-tests.log']:
    raw=(root/'evidence/recovery'/name).read_bytes()
    text=raw.decode('utf-16') if raw.startswith(b'\xff\xfe') else raw.decode('utf-8-sig',errors='replace')
    assert 'PASS:' in text,name
binding=json.loads((root/'evidence/recovery/parent-binding.json').read_text(encoding='utf-8'))
parent=Path(binding['source'])
if parent.exists():
    for name,digest in binding['files'].items():assert sha(parent/name)==digest,name
    assert sha(parent.with_suffix('.rar'))==binding['archive_sha256']
print(json.dumps({'status':'PASS','package_files_verified':count,'standalone_PC_only':True,'parent_checked':parent.exists()}))
