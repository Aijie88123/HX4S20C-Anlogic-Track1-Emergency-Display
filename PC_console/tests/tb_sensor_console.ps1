$ErrorActionPreference='Stop'
$sensorRoot=Split-Path -Parent $PSScriptRoot
$sensorOutput=Join-Path $sensorRoot 'evidence/ds18b20_console_20261029/console'
[void][IO.Directory]::CreateDirectory($sensorOutput)
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition ([IO.File]::ReadAllText($sensorRoot+'/tools/emergency_console_core.cs')+"`n"+[IO.File]::ReadAllText($sensorRoot+'/tests/console_fake_transport.cs')+"`n"+[IO.File]::ReadAllText($sensorRoot+'/tests/sensor_console_support.cs')) -ReferencedAssemblies System.Drawing
$sensorParseChecks=[SensorConsoleTests.Checks]::ParseFixtures($sensorRoot+'/evidence/ds18b20_console_20261029/wire_board/wire.txt')
. ($sensorRoot+'/tools/emergency_console.ps1') -NoShow
$ui.Timer.Stop();$script:sensorFake=[SensorConsoleTests.Transport]::new()
function New-ConsoleSession([string]$PortName){return [EmergencyConsole.Session]::new($script:sensorFake,35,25)}
$script:sensorGuiChecks=0;$script:capturedSensorErrors=@()
function Invoke-ConsoleUI([scriptblock]$Task){try{& $Task}catch{$script:capturedSensorErrors+=,$_.Exception.Message}}
function Assert-SensorGUI([bool]$Pass,[string]$Reason){$script:sensorGuiChecks++;if(!$Pass){throw ('SENSOR GUI: '+$Reason)}}
function Click-SensorGUI($Button){[void]$Button.GetType().GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic').Invoke($Button,@([EventArgs]::Empty))}
function Tick-SensorGUI{[void]$ui.Timer.GetType().GetMethod('OnTick',[Reflection.BindingFlags]'Instance,NonPublic').Invoke($ui.Timer,@([EventArgs]::Empty))}
function Wait-SensorGUI([scriptblock]$Condition,[string]$Reason){$watch=[Diagnostics.Stopwatch]::StartNew();while($watch.ElapsedMilliseconds -lt 5000){if(& $Condition){return};Start-Sleep -Milliseconds 10};throw ('SENSOR GUI WAIT: '+$Reason)}
function Save-SensorGUI([string]$Name){$ui.Form.PerformLayout();[Windows.Forms.Application]::DoEvents();$canvas=[Drawing.Bitmap]::new($ui.Form.Width,$ui.Form.Height);try{$ui.Form.DrawToBitmap($canvas,[Drawing.Rectangle]::new(0,0,$canvas.Width,$canvas.Height));$canvas.Save((Join-Path $sensorOutput ($Name+'.png')),[Drawing.Imaging.ImageFormat]::Png)}finally{$canvas.Dispose()}}
$ui.Form.StartPosition='Manual';$ui.Form.Location=[Drawing.Point]::new(-20000,-20000);$ui.Form.ShowInTaskbar=$false;$ui.Form.Show();[Windows.Forms.Application]::DoEvents();$ui.Timer.Stop()
try{
 Assert-SensorGUI (!$ui.TempClear.Enabled) 'disconnected clear disabled'
 $script:sensorFake.Set([SensorConsoleTests.Checks]::Status($false,401,1,0,0,0,0,16).Replace('ACK=1','ACK=0'))
 [void]$ui.Ports.Items.Add('COM_SENSOR_TEST');$ui.Ports.SelectedIndex=$ui.Ports.Items.Count-1;Click-SensorGUI $ui.Connect
 Wait-SensorGUI {$script:consoleSession.ReadView().Connected} 'connect sensor status';Tick-SensorGUI
 Assert-SensorGUI ($ui['探头温度'].Text -like '*25.0625*') 'real GUI fractional temperature'
 $script:sensorFake.Set([SensorConsoleTests.Checks]::Status($false,720,1,1,0,0,0,17).Replace('ACK=1','ACK=0'))
 Wait-SensorGUI {$script:sensorFake.Inner.CommitCount -ge 1} 'warning auto caption';Tick-SensorGUI
 Assert-SensorGUI (!$ui.Publish.Enabled -and !$ui.Clear.Enabled) 'warning caption protected'
 $script:sensorFake.Set([SensorConsoleTests.Checks]::Status($false,401,1,0,0,0,0,18).Replace('ACK=1','ACK=0'))
 Wait-SensorGUI {$script:sensorFake.Inner.ClearCount -ge 1} 'normal clears only owned nonemergency warning without command ACK'
 $script:sensorFake.Set([SensorConsoleTests.Checks]::Status($true,880,1,1,1,0,0,32))
 Wait-SensorGUI {$script:consoleSession.ReadView().Status.TempAlarm -eq 1 -and $script:sensorFake.Inner.CommitCount -ge 2} 'sensor fire caption';Tick-SensorGUI
 Assert-SensorGUI (!$ui.Stop.Enabled -and !$ui.TempClear.Enabled -and !$ui.EventButtons[1].Enabled -and $ui.Apply.Enabled) 'locked controls and allowed barriers'
 $script:consoleSession.ClearTemperatureAlarm()|Out-Null
 Wait-SensorGUI {$script:sensorFake.ClearRequests -eq 1 -and !$script:consoleSession.ReadView().Busy} 'hot clear rejected without disconnect'
 Assert-SensorGUI ($script:consoleSession.ReadView().Connected -and $script:consoleSession.ReadView().Status.TempAlarm -eq 1) 'rejection preserves session and lock'
 $script:sensorFake.Set([SensorConsoleTests.Checks]::Status($true,880,0,1,1,0,3,33))
 Wait-SensorGUI {$script:consoleSession.ReadView().Status.TempFault -eq 3} 'fault poll';Tick-SensorGUI
 Assert-SensorGUI ($ui['探头温度'].Text -like '*未知*' -and !$ui.TempClear.Enabled -and !$ui.Stop.Enabled) 'fault hides stale temperature and preserves lock';Save-SensorGUI 'sensor_fault_locked'
 $script:sensorFake.Set([SensorConsoleTests.Checks]::Status($true,800,1,1,1,1,0,34))
 Wait-SensorGUI {$script:consoleSession.ReadView().Status.TempClearAllowed -eq 1} 'cool qualification';Tick-SensorGUI
 Assert-SensorGUI $ui.TempClear.Enabled 'qualified manual clear button enabled'
 # Stress an actual click queued behind a complete130-frame bitmap.
 $ui.Auto.Checked=$false;Tick-SensorGUI;$script:sensorFake.Inner.WriteDelayMs=2
 $ui.Caption.Text='温度恢复演示，完整字幕事务后执行人工解除。';Click-SensorGUI $ui.Publish
 Wait-SensorGUI {$script:consoleSession.ReadView().Busy} 'bitmap started';Click-SensorGUI $ui.TempClear
 Wait-SensorGUI {$script:sensorFake.ClearRequests -eq 2 -and $script:consoleSession.ReadView().Status.TempAlarm -eq 0} 'manual clear through actual click';Tick-SensorGUI
 Assert-SensorGUI ($script:consoleSession.ReadView().Status.Emergency -and $ui.Stop.Enabled -and !$ui.TempClear.Enabled) 'clear lock does not send STOP'
 $trace=$script:sensorFake.Trace();$lastClear=[Array]::LastIndexOf($trace,'TEMP CLEAR');Assert-SensorGUI ($lastClear -gt 0 -and $trace[$lastClear-1] -eq 'STATUS?') 'queued clear waits complete upload and its state poll'
 Assert-SensorGUI ($script:sensorFake.ThreadSafe -and $script:sensorFake.Inner.ThreadSafe) 'single UART owner'
 Assert-SensorGUI (!($script:sensorFake.Inner.CommandSnapshot() -contains 'DEMO STOP')) 'no implicit STOP'
 Save-SensorGUI 'sensor_clear_confirmed'
 $script:consoleSession.ExportAudit((Join-Path $sensorOutput 'sensor-audit.csv'))
 Assert-SensorGUI ((Get-Content -LiteralPath (Join-Path $sensorOutput 'sensor-audit.csv') -Raw) -like '*温度状态*') 'temperature audit CSV'
 Click-SensorGUI $ui.Connect;Wait-SensorGUI {!$script:consoleSession.ReadView().Running} 'disconnect';Tick-SensorGUI
 Assert-SensorGUI ($ui['探头温度'].Text -like '*未知*' -and !$ui.TempClear.Enabled) 'disconnect invalidates temperature'
 Assert-SensorGUI ($script:capturedSensorErrors.Count -eq 0) 'no swallowed GUI error'
 @{status='PASS';parser_assertions=$sensorParseChecks;gui_assertions=$script:sensorGuiChecks;physical_COM=$false;render='Actual WinForms offscreen; simulated serial transport. Parser fixtures from current real-DQ RTL UART.'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $sensorOutput 'result.json') -Encoding UTF8
 Write-Output ('PASS: sensor parser '+$sensorParseChecks+' and GUI '+$script:sensorGuiChecks+' checks; signed/invalid values, warning/lock, protected controls, qualified clear, no implicit STOP, atomic130-frame queue, single UART owner and CSV')
}finally{$ui.Form.Close();$ui.Form.Dispose()}
