$ErrorActionPreference='Stop'
$hardwareRoot=Split-Path -Parent $PSScriptRoot
. ($hardwareRoot+'/tools/emergency_console.ps1') -NoShow -EnableRecoveryTests
$ui.Timer.Stop();$ui.Auto.Checked=$false;$script:portMonitor.Start()
function Tick-Hardware{[void]$ui.Timer.GetType().GetMethod('OnTick',[Reflection.BindingFlags]'Instance,NonPublic').Invoke($ui.Timer,@([EventArgs]::Empty))}
function Wait-Hardware([scriptblock]$condition,[string]$why){$w=[Diagnostics.Stopwatch]::StartNew();while($w.ElapsedMilliseconds -lt 18000){Tick-Hardware;if(& $condition){return};Start-Sleep -Milliseconds 50};throw ($why+': '+$script:recoveryText+'; '+$script:consoleSession.ReadView().LastError)}
$result=[ordered]@{at=[DateTimeOffset]::Now.ToString('o');physical_COM=$true;automatic_subtitles=$false;control_commands_sent=$false;captures=@();success=$false}
try{
 Wait-Hardware {$script:consoleSession -and $script:consoleSession.ReadView().Healthy} 'automatic discovery and read-only handshake'
 $result.device=$script:attemptId;$result.port=$script:attemptPort;$result.first=$script:consoleSession.ReadView().Status.Raw
 1..3|ForEach-Object{Start-Sleep -Milliseconds 1100;Tick-Hardware;$result.captures+=,$script:consoleSession.ReadView().Status.Raw}
 $ui.AutoConnect.Checked=$false;$script:consoleSession.Stop();Wait-Hardware {!$script:consoleSession.ReadView().Running} 'release serial handle'
 $closed=$script:consoleSession;Start-Sleep -Milliseconds 2200;Tick-Hardware
 if($script:consoleSession -ne $closed -or $closed.ReadView().Running){throw 'manual disconnect unexpectedly reconnected'}
 $result.manual_disconnect_stayed_closed=$true
 $ui.AutoConnect.Checked=$true
 Wait-Hardware {$script:consoleSession -ne $closed -and $script:consoleSession.ReadView().Healthy} 'reconnect fresh handshake'
 $result.second=$script:consoleSession.ReadView().Status.Raw;$result.reconnected=$true
 $result.last_device_state=$script:portState.Devices
 $script:consoleSession.ExportAudit($hardwareRoot+'/evidence/recovery/physical-readonly-audit.csv')
 $result.success=$true
 Write-Output ('PASS physical '+$result.port+' auto discovery, PING/full STATUS, temperature, release and reconnect; no controls or subtitles sent')
}catch{$result.error=$_.Exception.Message;Write-Output ('FAIL physical: '+$result.error)}
finally{
 $ui.AutoConnect.Checked=$false;if($script:consoleSession){$script:consoleSession.Dispose()};$script:portMonitor.Dispose();$ui.Form.Dispose()
 $result|ConvertTo-Json -Depth 6|Set-Content ($hardwareRoot+'/evidence/recovery/physical-readonly.json') -Encoding UTF8
}
if(!$result.success){exit 1}
