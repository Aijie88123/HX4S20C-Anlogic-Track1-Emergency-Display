$ErrorActionPreference='Stop'
$recoveryRoot=Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Drawing
Add-Type -Path @((Join-Path $recoveryRoot 'tools/emergency_console_core.cs'),(Join-Path $recoveryRoot 'tests/console_fake_transport.cs'),(Join-Path $recoveryRoot 'tools/serial_recovery.cs'),(Join-Path $recoveryRoot 'tests/recovery_support.cs')) -ReferencedAssemblies System.Drawing,System.Management
$policyChecks=[RecoveryTests.Checks]::Policy()
. ($recoveryRoot+'/tools/emergency_console.ps1') -NoShow -EnableRecoveryTests
$ui.Timer.Stop();$script:portMonitor.Dispose();$backend=[RecoveryTests.Backend]::new();$script:portMonitor=[EmergencyConsole.PortMonitor]::new($backend);$script:portMonitor.Start()
function New-ConsoleSession([string]$PortName){return [RecoveryTests.Pool]::Create()}
$script:checks=0
function Assert-R([bool]$ok,[string]$why){$script:checks++;if(!$ok){throw ('RECOVERY GUI: '+$why)}}
function Click-R($button){[void]$button.GetType().GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic').Invoke($button,@([EventArgs]::Empty))}
function Tick-R{[void]$ui.Timer.GetType().GetMethod('OnTick',[Reflection.BindingFlags]'Instance,NonPublic').Invoke($ui.Timer,@([EventArgs]::Empty))}
function Wait-R([scriptblock]$condition,[string]$why){$watch=[Diagnostics.Stopwatch]::StartNew();while($watch.ElapsedMilliseconds -lt 6000){Tick-R;if(& $condition){return};Start-Sleep -Milliseconds 10};throw ('RECOVERY WAIT: '+$why+'; '+$script:recoveryText)}
function Render-R([string]$file){$ui.Form.PerformLayout();[Windows.Forms.Application]::DoEvents();$im=[Drawing.Bitmap]::new($ui.Form.Width,$ui.Form.Height);try{$ui.Form.DrawToBitmap($im,[Drawing.Rectangle]::new(0,0,$im.Width,$im.Height));$im.Save($recoveryRoot+'/evidence/recovery/'+$file+'.png')}finally{$im.Dispose()}}
$ui.Form.StartPosition='Manual';$ui.Form.Location=[Drawing.Point]::new(-20000,-20000);$ui.Form.ShowInTaskbar=$false;$ui.Form.Show();$ui.Timer.Stop()
try{
 Wait-R {$script:portState.Revision -gt 0} 'initial scan'
 Assert-R (!$script:consoleSession -and $ui['连接状态'].Text -like '*等待*') 'start before power on waits'
 $backend.Set(10,'COM3',$false);$script:portMonitor.Refresh()
 Wait-R {$script:consoleSession -and $script:consoleSession.ReadView().Healthy} 'code10 repair and auto connect'
 Assert-R ($backend.Restarts -eq 1 -and $backend.LastTarget -eq [RecoveryTests.Backend]::Id) 'only matching code10 restarted'
 Assert-R (($ui.Ports.SelectedItem -eq 'COM3') -and $script:preferredId -eq [RecoveryTests.Backend]::Id) 'auto selection and pinned identity'
 Tick-R
 Assert-R (!$ui.Repair.Enabled) 'cannot reset an active serial owner'
 Assert-R (!$script:portMonitor.RequestRepair([RecoveryTests.Backend]::Id,$true,$true)) 'owner guard in backend request'
 $first=[RecoveryTests.Pool]::All[0]
 Assert-R (($first.Inner.CommandSnapshot()|Where-Object {$_ -notin @('PING','STATUS?')}).Count -eq 0) 'connection only read-only PING STATUS'
 # Lose a reply while the next control is queued. New session must never replay either.
 $first.Inner.DropControl=$true;$script:consoleSession.Request('DEMO FIRE')|Out-Null
 Wait-R {$first.Inner.CommandSnapshot() -contains 'DEMO FIRE'} 'control sent once'
 $script:consoleSession.Request('DEMO STOP')|Out-Null
 $backend.Set(-1,'',$false);$script:portMonitor.Refresh();$first.Fault=$true
 Wait-R {!$script:consoleSession.ReadView().Running} 'USB failure closes worker'
 Assert-R (!$ui.Publish.Enabled -and $ui['探头温度'].Text -like '*未知*') 'stale values invalidated immediately'
 Assert-R (($first.Inner.CommandSnapshot()|Where-Object {$_ -eq 'DEMO FIRE'}).Count -eq 1) 'lost response did not replay FIRE'
 Assert-R (!($first.Inner.CommandSnapshot() -contains 'DEMO STOP')) 'queued STOP discarded'
 Wait-R {$script:portState.Devices.Count -eq 0} 'device removed'
 Render-R 'waiting'
 $backend.Set(0,'COM8',$false);$script:portMonitor.Refresh()
 Wait-R {[RecoveryTests.Pool]::All.Count -eq 2 -and $script:consoleSession.ReadView().Healthy} 'replug changed COM automatically'
 $second=[RecoveryTests.Pool]::All[1]
 Assert-R ($script:attemptPort -eq 'COM8' -and $first.Disposed) 'old handle disposed before reopening renamed port'
 Assert-R (($second.Inner.CommandSnapshot()|Where-Object {$_ -notin @('PING','STATUS?')}).Count -eq 0) 'no control or subtitle replay in new normal session'
 $script:consoleSession.ExportAudit($recoveryRoot+'/evidence/recovery/reconnect-audit.csv')
 Assert-R ((Get-Content $recoveryRoot'/evidence/recovery/reconnect-audit.csv' -Raw) -like '*连接故障*') 'failure audit retained across reconnect'
 Render-R 'reconnected'
 Click-R $ui.Connect;Wait-R {!$script:consoleSession.ReadView().Running} 'manual disconnect'
 $script:retryAt=0;1..10|ForEach-Object{Tick-R}
 Assert-R (!$ui.AutoConnect.Checked -and [RecoveryTests.Pool]::All.Count -eq 2) 'manual disconnect stops reconnect'
 $backend.Set(0,'COM8',$true);$script:preferredId='';$script:targetPort='';$script:portMonitor.Refresh()
 Wait-R {$script:portState.Devices.Count -eq 2} 'two CH340s'
 $ui.AutoConnect.Checked=$true
 1..10|ForEach-Object{Tick-R}
 Assert-R ([RecoveryTests.Pool]::All.Count -eq 2) 'multiple adapters no guessing'
 # Explicit selection can open a busy port; access failure must not restart healthy hardware.
 [RecoveryTests.Pool]::DenyNext=$true;$ui.Ports.SelectedItem='COM8';Click-R $ui.Connect
 Wait-R {$script:consoleSession.ReadView().FailureKind -eq 'ACCESS' -and !$script:consoleSession.ReadView().Running} 'occupied port classified'
 Assert-R ($backend.Restarts -eq 1 -and $script:recoveryText -like '*占用*') 'busy serial never force-reset'
 $ui.AutoConnect.Checked=$false;$backend.Set(10,'COM3',$false);$backend.Denied=$true;$script:portMonitor.Refresh()
 Wait-R {$script:portState.Devices[0].Problem -eq 10} 'admin test fault inventory'
 Assert-R ($script:portMonitor.RequestRepair([RecoveryTests.Backend]::Id,$true,$false)) 'explicit repair queued'
 Wait-R {$script:portState.NeedsElevation} 'nonadmin repair requests explicit UAC button'
 Assert-R ($ui.Repair.Text -eq '管理员修复') 'administrator repair action visible'
 $before=$backend.Restarts;Assert-R (!$script:portMonitor.RequestRepair([RecoveryTests.Backend]::Id,$false,$false)) 'automatic restart cooldown enforced'
 Assert-R ($backend.Restarts -eq $before) 'no UAC or restart storm'
 @{status='PASS';policy_assertions=$policyChecks;gui_assertions=$script:checks;physical_COM=$false;coverage='start absent; code10 repair; unique/pinned/multiple; COM rename; lost control ACK; queue discard; fresh handshake; audit retention; manual stop; occupied port; admin UI; restart cooldown'}|ConvertTo-Json|Set-Content ($recoveryRoot+'/evidence/recovery/result.json') -Encoding UTF8
 Write-Output ('PASS: '+$policyChecks+' policy and '+$script:checks+' recovery GUI checks')
}finally{$ui.Form.Close();$ui.Form.Dispose()}
