$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
Add-Type -Path ($package+'/tools/serial_recovery.cs') -ReferencedAssemblies System.Management
$backend=[EmergencyConsole.WindowsDeviceBackend]::new();$before=$backend.Scan()
$target=[EmergencyConsole.RecoveryPolicy]::Target($before,'','')
if(!$target){throw '需要唯一B板CH340，停止修复测试'}
$result=[ordered]@{at=[DateTimeOffset]::Now.ToString('o');device=$target.Id;before=$before;physical_COM=$true;injected_code10=$false;success=$false}
try{
 $result.restart=$backend.Restart($target.Id)
 $w=[Diagnostics.Stopwatch]::StartNew()
 do{Start-Sleep -Milliseconds 250;$after=$backend.Scan();$d=[EmergencyConsole.RecoveryPolicy]::Target($after,$target.Id,'')}while($w.ElapsedMilliseconds -lt 12000 -and (!$d -or $d.Problem -ne 0 -or $after.Ports -notcontains $d.Port))
 if(!$d -or $d.Problem -ne 0 -or $after.Ports -notcontains $d.Port){throw 'CH340未恢复为可用端口'}
 $result.after=$after;$result.success=$true
 Write-Output 'PASS: exact CH340 restart via production repair backend; Windows reports healthy enumerated COM afterward; no injected hardware code10.'
}catch{$result.error=$_.Exception.Message;Write-Output ('FAIL: '+$result.error)}
$result|ConvertTo-Json -Depth 6|Set-Content ($package+'/evidence/recovery/physical-repair.json') -Encoding UTF8
if(!$result.success){exit 1}
