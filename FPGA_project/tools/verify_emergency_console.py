from pathlib import Path,PureWindowsPath
import json,hashlib,subprocess,sys
R=Path(__file__).resolve().parents[1];E=R/'evidence/emergency_console_20261027';read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'));sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
d=read(E/'production-scope.json');expected=d['production_files'];actual={}
for folder in ['common','assets']+[b+'/'+s for b in ['A_display','B_control'] for s in ['rtl','ip','vendor','constraints','project']]:
 for p in (R/folder).rglob('*'):
  if p.is_file() and 'smart_terminal_Runs' not in p.parts:actual[p.relative_to(R).as_posix()]=sha(p)
assert actual==expected,'Production inputs changed or added'
for name,h in d['firmware_hashes'].items():assert sha(R/name)==h,name
assert read(E/'console/result.json')['status']=='PASS'
s=(R/'tools/subtitle_sender.ps1').read_text(encoding='utf-8-sig');codec=s.split('Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"\n',1)[1].split('\n"@',1)[0];assert (R/'tools/emergency_console_core.cs').read_text(encoding='utf-8-sig').startswith(codec+'\n')
for script in ['verify_subtitle_reports.py','verify_native_resource.py']:subprocess.run([sys.executable,'-X','utf8',str(R/'tools'/script)],check=True)
print(f'PASS: emergency console; {len(actual)} parent production inputs/four firmware unchanged; no new FPGA resources or synthesis; no physical COM/HDMI acceptance claimed')
