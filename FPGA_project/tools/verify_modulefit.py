"""Read-only review verification; inherits source-exact native signoff, no recompilation."""
from pathlib import Path
import json,hashlib,subprocess,sys,re
R=Path(__file__).resolve().parents[1];E=R/'evidence/modulefit_20261030'
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper();read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
i=read(E/'inheritance.json');release=read(E/'release-check.json')
assert release['status']=='PASS' and release['production_changed']==0 and not release['native_rebuilt'] and not release['firmware_changed'] and not release['physical_test']
for n,v in i['parent_file_hashes'].items():
 assert h(R/n)==i['changed_documents'].get(n,v),n
actual={}
for folder in ['common','assets']+[b+'/'+s for b in ['A_display','B_control'] for s in ['rtl','ip','vendor','constraints','project']]:
 for p in (R/folder).rglob('*'):
  if p.is_file() and 'smart_terminal_Runs' not in p.parts:actual[p.relative_to(R).as_posix()]=h(p)
assert len(actual)==356 and actual==i['parent_production_hashes']
for n,v in i['firmware_hashes'].items():assert h(R/n)==v,n
count=0
for rel in release['new_reports']:
 d=read(E/rel);assert d['status']=='PASS' and d['physical_test'] is False
 for n,v in d['source_hashes'].items():assert h(R/n)==v,(rel,n);count+=1
d=read(E/'rc/result.json');assert len(d['cases'])==5
assert {(c['clk_hz'],c['c_pf']) for c in d['cases']}=={(1000000,25),(1000000,100),(1000000,220),(1000000,470),(25000000,470)}
assert all(c['r_ohm']==10000 and c['rise_ns']>0 for c in d['cases'])
audit=read(E/'module-audit.json');assert audit['R1_ohm']==10000 and audit['extra_pullup_required'] is False and audit['supply_v']==3.3 and audit['fpga_pull']=='NONE'
io=(R/'B_control/constraints/pin.adc').read_text();assert re.search(r'ds18b20_dq.*N12.*LVCMOS33.*PULLTYPE\s*=\s*NONE',io)
for n in ['README.md','DS18B20工程结合方案_20261029.md','DS18B20整板接入验证报告_20261029.md']:
 s=(R/n).read_text(encoding='utf-8');assert '10kΩ' in s and '无需外加上拉电阻' in s
 assert '没有时可用约4.7' not in s and '模块没有上拉时可加约4.7' not in s
subprocess.run([sys.executable,'-X','utf8',str(R/'tools/verify_ds18b20_console.py')],check=True)
print(f'PASS modulefit: all356 production inputs and all paired firmware unchanged; five10k delayed-rise protocol cases and module audit/{count} new bound inputs verified. Native timing/DRC inherited exactly; no new synthesis/routing/hardware test claimed.')
