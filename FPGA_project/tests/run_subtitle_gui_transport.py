from pathlib import Path
import subprocess,json,binascii,hashlib
R=Path(__file__).resolve().parents[1];O=R/'evidence/uart_subtitle_fixed_20261026/gui';PS='C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
s=(O/'fixed_gui_test.ps1').read_text(encoding='utf-8-sig')
start=s.index('function Send-Caption([string]$Name,$Image,[bool]$IsClear,[scriptblock]$Progress){',s.index('$script:dialogs=@();$script:sent=@()'))
end=s.index('\nfunction Invoke-TestClick',start)
mock=r'''
Add-Type -TypeDefinition @"
using System;using System.Collections.Generic;
public class CaptionFakeSerial {
 public bool IsOpen=true;public bool Disposed=false;public List<string> Frames=new List<string>();byte[] reply;int offset;
 static ushort Crc(byte[] a,int n){int c=65535;for(int j=0;j<n;j++){c^=a[j]<<8;for(int k=0;k<8;k++)c=((c&32768)!=0?((c<<1)^0x1021):(c<<1))&65535;}return(ushort)c;}
 public void Write(byte[] a,int start,int n){if(n!=33)throw new Exception("bad frame size");Frames.Add(BitConverter.ToString(a));reply=new byte[]{27,65,1,a[6],a[5],a[7],a[8],0,0,0};ushort c=Crc(reply,8);reply[8]=(byte)c;reply[9]=(byte)(c>>8);offset=0;}
 public int Read(byte[] a,int start,int n){int k=Math.Min(3,Math.Min(n,10-offset));Array.Copy(reply,offset,a,start,k);offset+=k;return k;}
 public void Close(){IsOpen=false;}public void Dispose(){Disposed=true;}
}
"@
function Open-CaptionPort([string]$Name){$serial=[CaptionFakeSerial]::new();$script:sent+=@{port=$Name;serial=$serial};return $serial}
'''
s=s[:start]+mock+s[end:];s=s.replace(str(O/'fixed.json'),str(O/'transport.json'))
h=O/'transport_gui_test.ps1';h.write_text(s,encoding='utf-8-sig');p=subprocess.run([PS,'-NoProfile','-STA','-File',str(h)],capture_output=True);(O/'transport.log').write_bytes(p.stdout+p.stderr);assert p.returncode==0,(p.stdout+p.stderr).decode(errors='replace')
b=json.loads((O/'transport.json').read_text(encoding='utf-8-sig'));cases=[]
for c in b['cases']:
 assert c['preview'] and not c['dialogs'] and c['buttons_restored'] and len(c['sent'])==1,c
 port=c['sent'][0]['serial'];assert port['Disposed'] and not port['IsOpen'];frames=[bytes.fromhex(x.replace('-','')) for x in port['Frames']];assert len(frames)==130
 payload=b''
 for i,f in enumerate(frames):
  q=f[3:31];assert f[:3]==bytes([27,83,1]) and binascii.crc_hqx(q,65535)==int.from_bytes(f[31:],'little')
  if 0<i<129:assert q[2]==1 and int.from_bytes(q[4:6],'little')==i-1;payload+=q[8:24]
 assert frames[0][5]==0 and frames[-1][5]==2 and len(payload)==2048 and int.from_bytes(frames[-1][9:11],'little')==binascii.crc_hqx(payload,65535)
 cases.append({'text':c['text'],'frames':130,'payload_bytes':2048,'partial_reply_read':True,'independent_crc':True,'progress_callback':True,'port_disposed':True})
assert b['blank']['no_send'] and b['blank']['dialogs'];cl=b['clear'];assert not cl['dialogs'] and len(cl['sent'])==1 and len(cl['sent'][0]['serial']['Frames'])==1
result=dict(status='PASS',cases=cases,clear=True,blank_no_open=True,root_causes=['PowerShell automatic $input shadows textbox in event callbacks','PowerShell dynamic scoping: Send-Caption $Progress argument shadows UI $progress in progress callback'],source_sha256=hashlib.sha256((R/'tools/subtitle_sender.ps1').read_bytes()).hexdigest(),physical_COM=False,desktop_click=False)
result['source_hashes']={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [R/'tools/subtitle_sender.ps1',R/'启动字幕工具.cmd',R/'tests/subtitle_sender_before_gui_fix.ps1',R/'tests/run_subtitle_gui_callbacks.py',Path(__file__)]}
(O/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(result,ensure_ascii=False,indent=2))
