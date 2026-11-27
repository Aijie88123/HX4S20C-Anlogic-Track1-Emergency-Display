from pathlib import Path
import subprocess,json
R=Path(__file__).resolve().parents[1];O=R/'evidence/uart_subtitle_fixed_20261026/gui';O.mkdir(parents=True,exist_ok=True);PS='C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
body=r'''
$script:dialogs=@();$script:sent=@()
function Send-Caption([string]$Name,$Image,[bool]$IsClear,[scriptblock]$Progress){$script:sent+=@{port=$Name;clear=$IsClear;width=$(if($Image){$Image.Width}else{0});crc=$(if($Image){[int][SubtitleCodec]::Crc($Image.Data,2048)}else{0})};if($Progress){& $Progress 128}}
function Invoke-TestClick($Button){$m=$Button.GetType().GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic');[void]$m.Invoke($Button,@([EventArgs]::Empty))}
$box=@($form.Controls|Where-Object {$_ -is [Windows.Forms.TextBox]})[0]
[void]$ports.Items.Add('COM_TEST');$ports.SelectedIndex=0
$cases=@()
foreach($message in @('紧急通知：请按绿色路线疏散 EXIT A','Hello FPGA 123','请')){
 $box.Text=$message;$script:dialogs=@();$script:sent=@();Invoke-TestClick $preview
 $previewOk=($null -ne $picture.Image -and $status.Text.StartsWith('预览：'))
 Invoke-TestClick $send
 $cases+=@{text=$message;preview=$previewOk;sent=$script:sent;dialogs=$script:dialogs;buttons_restored=($send.Enabled -and $preview.Enabled -and $clearButton.Enabled -and $refresh.Enabled)}
}
$box.Text='   ';$script:dialogs=@();$script:sent=@();Invoke-TestClick $send
$blank=@{no_send=($script:sent.Count -eq 0);dialogs=$script:dialogs;buttons_restored=$send.Enabled}
$script:dialogs=@();$script:sent=@();Invoke-TestClick $clearButton
$clearResult=@{sent=$script:sent;dialogs=$script:dialogs}
@{cases=$cases;blank=$blank;clear=$clearResult;method='Actual WinForms registered Click delegates via OnClick; mocked transport only; no desktop clicking or physical COM'}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath '__RESULT__' -Encoding UTF8
$form.Dispose()
'''
for name,tool in [('original',R/'tests/subtitle_sender_before_gui_fix.ps1'),('fixed',R/'tools/subtitle_sender.ps1')]:
 s=tool.read_text(encoding='utf-8-sig')
 for title in ['预览失败','发送失败','清除失败']:
  s=s.replace("[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'"+title+"')", "$script:dialogs+=@{title='"+title+"';message=$_.Exception.Message}")
 tail='$refresh.PerformClick();$preview.PerformClick();[void]$form.ShowDialog()'
 assert tail in s;s=s.replace(tail,body.replace('__RESULT__',str(O/(name+'.json'))))
 h=O/(name+'_gui_test.ps1');h.write_text(s,encoding='utf-8-sig');p=subprocess.run([PS,'-NoProfile','-STA','-File',str(h)],capture_output=True);(O/(name+'.log')).write_bytes(p.stdout+p.stderr);assert p.returncode==0,(p.stdout+p.stderr).decode(errors='replace')
a=json.loads((O/'original.json').read_text(encoding='utf-8-sig'));b=json.loads((O/'fixed.json').read_text(encoding='utf-8-sig'))
assert all(not c['preview'] and not c['sent'] and c['dialogs'] for c in a['cases']),a
assert all(c['preview'] and len(c['sent'])==1 and c['sent'][0]['width']>0 and not c['dialogs'] and c['buttons_restored'] for c in b['cases']),b
assert b['blank']['no_send'] and b['blank']['dialogs'] and b['blank']['buttons_restored']
assert len(b['clear']['sent'])==1 and b['clear']['sent'][0]['clear'] and not b['clear']['dialogs']
print('PASS: reproduced old GUI empty-text bug in all 3 cases; fixed actual preview/send callbacks, blank rejection and clear callbacks.')
print(json.dumps(b,ensure_ascii=False,indent=2))
