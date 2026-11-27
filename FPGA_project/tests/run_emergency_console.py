from pathlib import Path
import subprocess,json,hashlib,binascii,re
R=Path(__file__).resolve().parents[1];E=R/'evidence/emergency_console_20261027/console';E.mkdir(parents=True,exist_ok=True);PS='C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
old=(R/'tools/subtitle_sender.ps1').read_text(encoding='utf-8-sig');codec=old.split('Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"\n',1)[1].split('\n"@',1)[0]
core=(R/'tools/emergency_console_core.cs').read_text(encoding='utf-8-sig');assert core.startswith(codec+'\n'),'The established codec must remain byte-for-byte unchanged as C# text'
logs={}
for name in ['core','gui']:
 p=subprocess.run([PS,'-NoProfile','-STA','-File',str(R/f'tests/tb_emergency_console_{name}.ps1')],capture_output=True,timeout=120)
 s=(p.stdout+p.stderr).decode(errors='replace');(E/(name+'.log')).write_text(s,encoding='utf-8');assert p.returncode==0 and 'PASS:' in s,s;logs[name]=s.strip();print(s.strip())
frames=(E/'wire_frames.txt').read_text().splitlines();uploads=0;clears=0;expected=None;payload=b''
for line in frames:
 f=bytes.fromhex(line.replace('-',''));q=f[3:31];assert len(f)==33 and f[:3]==bytes([27,83,1]) and binascii.crc_hqx(q,65535)==int.from_bytes(f[31:],'little') and q[:2]==bytes([18,1]) and q[24:]==b'1BUS'
 op,tag=q[2:4];idx=int.from_bytes(q[4:6],'little')
 if op==0:assert expected is None and 16<=idx<=1024 and idx%16==0;expected=0;held=tag;payload=b''
 elif op==1:assert idx==expected and tag==held;payload+=q[8:24];expected+=1
 elif op==2:assert expected==128 and idx==128 and len(payload)==2048 and tag==held and binascii.crc_hqx(payload,65535)==int.from_bytes(q[6:8],'little');uploads+=1;expected=None
 elif op==3:assert expected is None and idx==0;clears+=1
 else:raise AssertionError(op)
assert expected is None and uploads>=5 and clears>=1
assert (E/'audit.csv').read_bytes().startswith(b'\xef\xbb\xbf') and (E/'board.csv').read_bytes().startswith(b'\xef\xbb\xbf')
inputs=[R/'tools/emergency_console_core.cs',R/'tools/emergency_console.ps1',R/'启动应急管理控制台.cmd',R/'tools/subtitle_sender.ps1',R/'tests/console_fake_transport.cs',R/'tests/tb_emergency_console_core.ps1',R/'tests/tb_emergency_console_gui.ps1',Path(__file__),R/'evidence/uart_service_20261026/link/wire.txt',Path('C:/Windows/Fonts/msyh.ttc')]
outputs=[E/n for n in ['wire_frames.txt','transactions.txt','audit.csv','board.csv','gui.json','console_fire.png','console_no_route.png','console_offline.png']]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
result=dict(status='PASS',source_hashes={str(p):sha(p) for p in inputs},generated_hashes={str(p):sha(p) for p in outputs},core=logs['core'],gui=json.loads((E/'gui.json').read_text(encoding='utf-8-sig')),independent_wire_audit=dict(frames=len(frames),uploads=uploads,clears=clears,all_packet_crc=True,all_image_crc=True,block_order_and_tags=True),established_codec_source_exact=True,physical_COM=False,mouse_clicks=False,hardware_test=False,new_synthesis_or_route=False,limitations=['Serial transport is simulated; no physical CH340/USB/HDMI acceptance','GUI registered delegates programmatically invoked; offscreen WinForms render, not mouse/desktop acceptance','Existing actual-RTL status fixtures validate parser semantics; no sensor or physical fire detection claimed'])
(E/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(result['independent_wire_audit']))
