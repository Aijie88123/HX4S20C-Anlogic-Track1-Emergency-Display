$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition ([IO.File]::ReadAllText($projectRoot+'/tools/emergency_console_core.cs')+"`n"+[IO.File]::ReadAllText($projectRoot+'/tests/console_fake_transport.cs')) -ReferencedAssemblies System.Drawing
. ($projectRoot+'/tools/emergency_console.ps1') -NoShow
$ui.Timer.Stop()
$script:fakePort=[ConsoleTests.FakeTransport]::new()
function New-ConsoleSession([string]$PortName){return [EmergencyConsole.Session]::new($script:fakePort,35,25)}
$script:capturedErrors=@()
function Invoke-ConsoleUI([scriptblock]$Task){try{& $Task}catch{$script:capturedErrors+=,$_.Exception.Message}}
$script:guiChecks=0
function Assert-GUI([bool]$Pass,[string]$Reason){$script:guiChecks++;if(!$Pass){throw ('GUI ASSERT: '+$Reason)}}
function Invoke-GUIButton($Button){[void]$Button.GetType().GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic').Invoke($Button,@([EventArgs]::Empty))}
function Tick-GUI{[void]$ui.Timer.GetType().GetMethod('OnTick',[Reflection.BindingFlags]'Instance,NonPublic').Invoke($ui.Timer,@([EventArgs]::Empty))}
function Wait-GUI([scriptblock]$Condition,[string]$Reason){$watch=[Diagnostics.Stopwatch]::StartNew();while($watch.ElapsedMilliseconds -lt 4000){if(& $Condition){return};Start-Sleep -Milliseconds 10};throw ('GUI WAIT: '+$Reason)}
function Save-ConsoleRender([string]$Name){$ui.Form.PerformLayout();[Windows.Forms.Application]::DoEvents();$canvas=[Drawing.Bitmap]::new($ui.Form.Width,$ui.Form.Height);try{$ui.Form.DrawToBitmap($canvas,[Drawing.Rectangle]::new(0,0,$canvas.Width,$canvas.Height));$canvas.Save(($projectRoot+'/evidence/emergency_console_20261027/console/'+$Name+'.png'),[Drawing.Imaging.ImageFormat]::Png)}finally{$canvas.Dispose()}}
$ui.Form.StartPosition='Manual';$ui.Form.Location=[Drawing.Point]::new(-20000,-20000);$ui.Form.ShowInTaskbar=$false;$ui.Form.Show();[Windows.Forms.Application]::DoEvents();$ui.Timer.Stop()
try{
 Assert-GUI ($ui.Form.Height -le [Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height) 'window fits working area'
 Assert-GUI (!$ui.Publish.Enabled -and !$ui.Stop.Enabled -and !$ui.Apply.Enabled) 'disconnected controls disabled'
 $ui.Caption.Text='校园通知：请熟悉疏散出口 EXIT A';Invoke-GUIButton $ui.Preview
 Assert-GUI ($null -ne $ui.Picture.Image -and $ui.Picture.Image.Width -gt 0) 'preview callback gets actual textbox body'
 [void]$ui.Ports.Items.Add('COM_TEST');$ui.Ports.SelectedIndex=$ui.Ports.Items.Count-1;Invoke-GUIButton $ui.Connect
 Wait-GUI {$script:consoleSession.ReadView().Connected} 'connect handshake';Tick-GUI
 Assert-GUI ($ui['连接状态'].Text -like '*双板在线*') 'USB and board link status'
 Assert-GUI ($ui['板端实际事件'].Text -eq '正常轮播') 'actual normal'
 Invoke-GUIButton $ui.Publish;Wait-GUI {$script:fakePort.CommitCount -eq 1 -and !$script:consoleSession.ReadView().Busy} 'publish through actual click';Tick-GUI
 Assert-GUI ($ui.Progress.Value -eq 128) 'progress without variable shadowing'
 Invoke-GUIButton $ui.EventButtons[0];Wait-GUI {$script:fakePort.CommandSnapshot() -contains 'DEMO FIRE'} 'fire button sends correct tag'
 $script:fakePort.Set([ConsoleTests.Checks]::Fire());Wait-GUI {$script:consoleSession.ReadView().Status.Act -eq 1 -and !$script:consoleSession.ReadView().RequestPending} 'actual fire applied';Tick-GUI
 Assert-GUI ($ui['板端实际事件'].Text -eq '火灾应急') 'fire actual card'
 Assert-GUI ($ui['当前疏散路线'].Text -eq '4号南出口') 'qualified exit card'
 Assert-GUI ($ui.Form.Height -le [Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height) 'window fits working area'
 Assert-GUI (!$ui.Publish.Enabled -and !$ui.Clear.Enabled) 'system notice takes priority'
 Wait-GUI {$script:fakePort.CommitCount -ge 2} 'auto fire bitmap commit';Tick-GUI;Save-ConsoleRender 'console_fire'
 $ui.Barrier.SelectedIndex=3;Invoke-GUIButton $ui.Apply;Wait-GUI {$script:fakePort.CommandSnapshot() -contains 'BARRIER SET 3'} 'barrier UI';Tick-GUI;Assert-GUI (!($ui.RouteDetail.Text -like '*推荐4号南出口*')) 'pending request suppresses old exit in route details'
 $script:fakePort.Set([ConsoleTests.Checks]::Fire().Replace('BAR=0','BAR=3').Replace('CLOSED=0080','CLOSED=F080').Replace('EXIT=4','EXIT=0').Replace('ROUTE=8010','ROUTE=0000'))
 Wait-GUI {$script:consoleSession.ReadView().Status.Bar -eq 3 -and !$script:consoleSession.ReadView().RequestPending} 'no-route applied';Tick-GUI
 Assert-GUI ($ui['当前疏散路线'].Text -eq '未返回可用路线') 'no route card'
 Assert-GUI ($ui.AutoText.Text -like '*暂无可用路线*') 'no false exit in auto preview'
 Save-ConsoleRender 'console_no_route'
 Invoke-GUIButton $ui.ReadLog;Wait-GUI {$script:consoleSession.ReadView().BoardLogCount -eq 3} 'log read';Tick-GUI
 Assert-GUI ($ui.BoardList.Items.Count -eq 3 -and $ui.ExportBoard.Enabled) 'complete snapshot rows'
 $ui.Auto.Checked=$false;Assert-GUI (!$script:consoleSession.ReadView().Auto) 'checkbox delegates to session'
 Tick-GUI;Assert-GUI $ui.Publish.Enabled 'explicit manual mode allows publication'
 $ui.Caption.Text='';Invoke-GUIButton $ui.Preview;Assert-GUI ($script:capturedErrors.Count -eq 1) 'blank preview rejected'
 Invoke-GUIButton $ui.Connect;Wait-GUI {!$script:consoleSession.ReadView().Running} 'disconnect worker';Tick-GUI
 Assert-GUI ($ui['板端实际事件'].Text -like '*未知*' -and !$ui.Publish.Enabled) 'disconnect invalidates actual card'
 Assert-GUI (!($script:fakePort.CommandSnapshot() -contains 'DEMO STOP')) 'disconnect never sends STOP'
 Assert-GUI $script:fakePort.ThreadSafe 'GUI uses single serial owner'
 Save-ConsoleRender 'console_offline'
 @{status='PASS';assertions=$script:guiChecks;actual_click_delegates=$true;physical_COM=$false;mouse_clicks=$false;render='Offscreen actual WinForms DrawToBitmap; simulated transport only'}|ConvertTo-Json|Set-Content ($projectRoot+'/evidence/emergency_console_20261027/console/gui.json') -Encoding UTF8
 Write-Output ('PASS: '+$script:guiChecks+' GUI callbacks and state cards; offscreen rendering, simulated serial only')
}finally{$ui.Form.Close();$ui.Form.Dispose()}
