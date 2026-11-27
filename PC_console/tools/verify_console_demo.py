from pathlib import Path
import hashlib,json
R=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
n=0
for line in (R/'SHA256SUMS.txt').read_text(encoding='utf-8-sig').splitlines():
    digest,name=line.split('  ',1);p=(R/name).resolve();assert p.is_relative_to(R) and p.is_file(),name
    assert sha(p)==digest,name;n+=1
demo=read(R/'evidence/demo/result.json');assert demo['status']=='PASS' and demo['assertions']==46
hdmi=read(R/'evidence/demo/hdmi/result.json');assert hdmi['status']=='PASS' and hdmi['RTL_exact_pixel_samples']==563200 and not hdmi['physical_HDMI']
for name in ['core-regression.log','gui-regression.log','sensor-regression.log','recovery-regression.log','demo-tests.log','hdmi-test.log']:
    raw=(R/'evidence/demo'/name).read_bytes();text=raw.decode('utf-16') if raw.startswith(b'\xff\xfe') else raw.decode('utf-8-sig',errors='replace');assert 'PASS:' in text,name
original_root=Path('D:/HX4S20C_console_demo_seriallast_20261031')
for name,digest in hdmi['source_hashes'].items():
    p=Path(name)
    try:rel=p.relative_to(original_root);p=R/rel
    except ValueError:pass
    if p.exists():assert sha(p)==digest,name
parent=read(R/'evidence/demo/parent-binding.json')
for archive,digest in [(Path(parent['parent_console']).with_suffix('.zip'),parent['parent_console_zip_sha256']),(Path(parent['FPGA_best']).with_suffix('.rar'),parent['FPGA_best_rar_sha256'])]:
    if archive.exists():assert sha(archive)==digest,str(archive)
print(json.dumps({'status':'PASS','package_files':n,'new_demo_assertions':46,'RTL_pixels':563200,'FPGA_firmware_changed':False}))
