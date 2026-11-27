$ErrorActionPreference='Stop'
$demoProject=Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition ([IO.File]::ReadAllText($demoProject+'/tools/emergency_console_core.cs')+"`n"+[IO.File]::ReadAllText($demoProject+'/tests/console_fake_transport.cs')+"`n"+[IO.File]::ReadAllText($demoProject+'/tests/sensor_console_support.cs')) -ReferencedAssemblies System.Drawing
. ($demoProject+'/tools/emergency_console.ps1') -NoShow
$ui.Timer.Stop();$script:demoFake=[SensorConsoleTests.Transport]::new()
function New-ConsoleSession([string]$PortName){return [EmergencyConsole.Session]::new($script:demoFake,35,25)}
$script:demoChecks=0;$script:demoErrors=@();$script:demoTestSeconds=0
function Invoke-ConsoleUI([scriptblock]$Task){try{& $Task}catch{$script:demoErrors+=,$_.Exception.Message}}
function Get-DemoElapsed{return $script:demoTestSeconds}
function Assert-Demo([bool]$ok,[string]$why){$script:demoChecks++;if(!$ok){throw ('DEMO: '+$why)}}
function Click-Demo($button){[void]$button.GetType().GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic').Invoke($button,@([EventArgs]::Empty))}
function Tick-Demo{[void]$ui.Timer.GetType().GetMethod('OnTick',[Reflection.BindingFlags]'Instance,NonPublic').Invoke($ui.Timer,@([EventArgs]::Empty))}
function Wait-Demo([scriptblock]$condition,[string]$why){$w=[Diagnostics.Stopwatch]::StartNew();while($w.ElapsedMilliseconds -lt 5000){Tick-Demo;if(& $condition){return};Start-Sleep -Milliseconds 10};throw ('DEMO WAIT: '+$why)}
function Render-Demo([string]$name){$ui.Form.PerformLayout();[Windows.Forms.Application]::DoEvents();$bitmap=[Drawing.Bitmap]::new($ui.Form.Width,$ui.Form.Height);try{$ui.Form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height));$bitmap.Save($demoProject+'/evidence/demo/'+$name+'.png')}finally{$bitmap.Dispose()}}
function Control-Count{return @($script:demoFake.Inner.CommandSnapshot()|Where-Object {$_ -notin @('PING','STATUS?')}).Count}
$ui.Form.StartPosition='Manual';$ui.Form.Location=[Drawing.Point]::new(-20000,-20000);$ui.Form.ShowInTaskbar=$false
$keyMethod=$ui.Form.GetType().GetMethod('OnKeyDown',[Reflection.BindingFlags]'Instance,NonPublic')
[void]$keyMethod.Invoke($ui.Form,@([Windows.Forms.KeyEventArgs]::new([Windows.Forms.Keys]::F11)))
Assert-Demo ($script:demoFullscreen -and $ui.Form.FormBorderStyle -eq 'None') 'F11 presentation fullscreen'
[void]$keyMethod.Invoke($ui.Form,@([Windows.Forms.KeyEventArgs]::new([Windows.Forms.Keys]::Escape)))
Assert-Demo (!$script:demoFullscreen -and $ui.Form.FormBorderStyle -eq 'Sizable') 'Escape restores normal window'
$ui.Form.Location=[Drawing.Point]::new(-20000,-20000);$ui.Form.Show();$ui.Timer.Stop()
$captionRows=@()
try{
 Tick-Demo
 Assert-Demo ($ui.DemoTabs.TabCount -eq 5 -and $ui.DemoTabs.SelectedTab -eq $ui.DemoTab) 'presentation homepage selected with all original tools retained'
 Assert-Demo (!$ui.DemoFire.Enabled -and !$ui.DemoPublish.Enabled -and !$ui.DemoTempClear.Enabled) 'no enabled commands while disconnected'
 Assert-Demo ((Get-DemoBudgets|Measure-Object -Sum).Sum -eq 180) 'three-minute schedule totals180'
 $ui.DemoMode.SelectedIndex=1;Assert-Demo ((Get-DemoBudgets|Measure-Object -Sum).Sum -eq 240) 'four-minute schedule totals240';$ui.DemoMode.SelectedIndex=0
 Click-Demo $ui.DemoStart;Assert-Demo $script:demoWatch.IsRunning 'timer start';Click-Demo $ui.DemoStart;Assert-Demo (!$script:demoWatch.IsRunning) 'timer pause'
 for($i=0;$i -lt 6;$i++){Click-Demo $ui.DemoStageButtons[$i];Assert-Demo ($ui.DemoTitle.Text -like ($script:demoSteps[$i].Title+'*')) ('step '+$i+' cue');Assert-Demo ((Control-Count) -eq 0) 'navigation cannot issue commands'
  $image=[SubtitleCodec]::Raster($script:demoSteps[$i].Caption);try{Assert-Demo ($image.Width -le 640) 'stage caption fits1280px at2x';$image.Preview.Save($demoProject+'/evidence/demo/caption-'+$i+'.png');$captionRows+=@{kind='stage';text=$script:demoSteps[$i].Caption;source_width=$image.Width;HDMI_width=$image.Width*2}}finally{$image.Preview.Dispose()}
 }
 $script:demoTestSeconds=181;Tick-Demo;Assert-Demo ($ui.DemoProgress.Value -eq 180 -and $ui.DemoPhaseHint.Text -like '*目标时长*') 'overtime is reminder only'
 Assert-Demo ((Control-Count) -eq 0) 'overtime has no control effects';Click-Demo $ui.DemoReset;$script:demoTestSeconds=0
 $script:demoFake.Set([SensorConsoleTests.Checks]::Status($false,400,1,0,0,0,0,16));[void]$ui.Ports.Items.Add('COM_DEMO_TEST');$ui.Ports.SelectedItem='COM_DEMO_TEST';Click-Demo $ui.Connect
 Wait-Demo {$script:consoleSession.ReadView().Healthy} 'normal sensor connection';Tick-Demo
 Assert-Demo ($ui.DemoPublish.Enabled -and $ui.DemoFire.Enabled -and !$ui.DemoBarrier.Enabled) 'normal commands and no premature barrier'
 Set-DemoStage 4;Click-Demo $ui.DemoPublish
 Wait-Demo {$script:demoFake.Inner.CommitCount -eq 1 -and !$script:consoleSession.ReadView().Busy} 'stage caption complete upload'
 Assert-Demo ($script:demoFake.Inner.Frames().Length -eq 130) 'stage caption uses original complete130-frame transaction'
 Assert-Demo ($ui.Caption.Text -eq $script:demoSteps[4].Caption) 'preset can be edited in existing subtitle panel'
 Click-Demo $ui.DemoFire;Wait-Demo {$script:demoFake.Inner.CommandSnapshot() -contains 'DEMO FIRE'} 'explicit fire shortcut'
 Assert-Demo ((@($script:demoFake.Inner.CommandSnapshot()|Where-Object {$_ -eq 'DEMO FIRE'})).Count -eq 1) 'explicit click single fire request'
 $script:demoFake.Set([SensorConsoleTests.Checks]::Status($true,880,1,1,1,0,0,32));Wait-Demo {$script:consoleSession.ReadView().Status.TempAlarm -eq 1 -and $script:demoFake.Inner.CommitCount -ge 2} 'locked actual sensor event';Tick-Demo
 Assert-Demo (!$ui.DemoFire.Enabled -and !$ui.DemoStop.Enabled -and !$ui.DemoTempClear.Enabled -and $ui.DemoBarrier.Enabled) 'temperature lock preserved in every shortcut'
 Assert-Demo (!$ui.DemoPublish.Enabled) 'ordinary stage captions cannot overwrite automatic emergency caption'
 Set-DemoStage 3;Render-Demo 'demo-alarm'
 $count=Control-Count;1..6|ForEach-Object{Click-Demo $ui.DemoNext;Click-Demo $ui.DemoPrevious};$script:demoTestSeconds=300;Tick-Demo
 Assert-Demo ((Control-Count) -eq $count) 'connected navigation and overtime never dispatch controls'
 $script:demoFake.Set([SensorConsoleTests.Checks]::Status($true,800,1,1,1,1,0,33));Wait-Demo {$script:consoleSession.ReadView().Status.TempClearAllowed -eq 1} 'qualified cooling';Tick-Demo
 Assert-Demo $ui.DemoTempClear.Enabled 'manual clear requires real qualifying state'
 Click-Demo $ui.DemoTempClear;Wait-Demo {$script:consoleSession.ReadView().Status.TempAlarm -eq 0} 'clear shortcut';Tick-Demo
 Assert-Demo ($ui.DemoStop.Enabled -and !($script:demoFake.Inner.CommandSnapshot() -contains 'DEMO STOP')) 'clear does not implicitly STOP'
 $script:demoFake.Set([SensorConsoleTests.Checks]::Status($false,400,1,0,0,0,0,34));Wait-Demo {!$script:consoleSession.ReadView().Status.Emergency} 'back to normal';Tick-Demo
 $script:demoTestSeconds=85;Set-DemoStage 2;Render-Demo 'demo-home'
 $ui.Form.Size=[Drawing.Size]::new(1060,740);Render-Demo 'demo-compact'
 Assert-Demo ($ui.DemoNext.Right -le $ui.DemoNext.Parent.ClientSize.Width) 'navigation remains within compact layout'
 Assert-Demo (@($ui.DemoStageButtons|Where-Object {$_.Height -lt 20 -or $_.Bottom -gt $_.Parent.ClientSize.Height}).Count -eq 0) 'all six steps visible on compact window'
 $autoStates=@([SensorConsoleTests.Checks]::Status($true,880,1,1,1,0,0,40),[SensorConsoleTests.Checks]::Status($false,720,1,1,0,0,0,41),[ConsoleTests.Checks]::Fire(),[ConsoleTests.Checks]::Fire().Replace('EXIT=4','EXIT=0').Replace('ROUTE=8010','ROUTE=0000'),[ConsoleTests.Checks]::Fire().Replace('FRESH=1','FRESH=0'))
 foreach($line in $autoStates){$caption=[EmergencyConsole.Policy]::Caption([EmergencyConsole.BoardStatus]::Parse($line));$image=[SubtitleCodec]::Raster($caption);try{Assert-Demo ($image.Width -le 640) 'automatic caption fits a1280px line';$captionRows+=@{kind='automatic';text=$caption;source_width=$image.Width;HDMI_width=$image.Width*2}}finally{$image.Preview.Dispose()}}
 Assert-Demo ($script:demoFake.ThreadSafe -and $script:demoFake.Inner.ThreadSafe) 'new actions retain single serial owner'
 Assert-Demo ($script:demoErrors.Count -eq 0) 'no swallowed GUI error'
 $captionRows|ConvertTo-Json -Depth 3|Set-Content ($demoProject+'/evidence/demo/caption-widths.json') -Encoding UTF8
 @{steps=$script:demoSteps;three_minute_budgets=@(25,30,45,35,25,20);four_minute_budgets=@(30,40,60,50,35,25)}|ConvertTo-Json -Depth 5|Set-Content ($demoProject+'/evidence/demo/guide.json') -Encoding UTF8
 @{status='PASS';assertions=$script:demoChecks;physical_COM=$false;physical_HDMI=$false;GUI='Actual offscreen WinForms delegates and rendering';scope='guide timings/no implicit commands/guarded actions/atomic subtitle transaction/temperature lock/caption widths'}|ConvertTo-Json|Set-Content ($demoProject+'/evidence/demo/result.json') -Encoding UTF8
 Write-Output ('PASS: '+$script:demoChecks+' demo UI and HDMI caption checks')
}finally{$ui.Form.Close();$ui.Form.Dispose()}
