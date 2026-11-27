param([switch]$NoShow,[switch]$EnableRecoveryTests)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if(-not ('EmergencyConsole.Session' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'emergency_console_core.cs') -ReferencedAssemblies System.Drawing}
if(-not ('EmergencyConsole.PortMonitor' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'serial_recovery.cs') -ReferencedAssemblies System.Management}
[Windows.Forms.Application]::EnableVisualStyles()
$script:consoleSession=$null
$script:lastBoardLogRevision=-1
$script:ui=@{}
$ui.Form=[Windows.Forms.Form]::new();$ui.Form.Text='校园应急信息发布与疏散指挥终端 · 现场演示版';$ui.Form.KeyPreview=$true;$ui.Form.Size=[Drawing.Size]::new(1160,860);$ui.Form.MinimumSize=[Drawing.Size]::new(1060,760);$ui.Form.StartPosition='CenterScreen';$ui.Form.BackColor=[Drawing.ColorTranslator]::FromHtml('#0B1729');$ui.Form.ForeColor=[Drawing.ColorTranslator]::FromHtml('#DBE9F4');$ui.Form.Font=[Drawing.Font]::new('Microsoft YaHei',9)
$consoleWorkingArea=[Windows.Forms.Screen]::PrimaryScreen.WorkingArea;$ui.Form.Size=[Drawing.Size]::new([Math]::Min(1160,$consoleWorkingArea.Width-20),[Math]::Min(860,$consoleWorkingArea.Height-20));$ui.Form.MinimumSize=[Drawing.Size]::new([Math]::Min(1060,$consoleWorkingArea.Width-20),[Math]::Min(700,$consoleWorkingArea.Height-20))
function New-ConsoleSession([string]$PortName){return [EmergencyConsole.Session]::new([EmergencyConsole.SerialTransport]::new($PortName))}
function New-ConsoleButton([string]$Caption,[int]$Width=112){$b=[Windows.Forms.Button]::new();$b.Text=$Caption;$b.Width=$Width;$b.Height=34;$b.FlatStyle='Flat';$b.BackColor=[Drawing.ColorTranslator]::FromHtml('#173B54');$b.ForeColor=[Drawing.Color]::White;$b.Margin=[Windows.Forms.Padding]::new(5);return $b}
function New-ConsoleLabel([string]$Caption){$c=[Windows.Forms.Label]::new();$c.Text=$Caption;$c.AutoSize=$true;$c.Margin=[Windows.Forms.Padding]::new(5,8,5,4);return $c}
function New-ConsoleGroup([string]$Caption){$g=[Windows.Forms.GroupBox]::new();$g.Text=$Caption;$g.Dock='Fill';$g.Padding=[Windows.Forms.Padding]::new(12);$g.Margin=[Windows.Forms.Padding]::new(6);$g.ForeColor=[Drawing.ColorTranslator]::FromHtml('#B8DBE8');return $g}
function Invoke-ConsoleUI([scriptblock]$Task){try{& $Task}catch{$ui.Footer.Text=$_.Exception.Message;[void][Windows.Forms.MessageBox]::Show($ui.Form,$_.Exception.Message,'操作未完成')}}
function Add-ConsoleRow($List,[string[]]$Values){$item=[Windows.Forms.ListViewItem]::new($Values[0]);for($rowColumn=1;$rowColumn -lt $Values.Length;$rowColumn++){[void]$item.SubItems.Add($Values[$rowColumn])};[void]$List.Items.Add($item)}
function New-ConsoleList([string[]]$Columns,[int[]]$Widths){$l=[Windows.Forms.ListView]::new();$l.Dock='Fill';$l.View='Details';$l.FullRowSelect=$true;$l.GridLines=$false;$l.BackColor=[Drawing.ColorTranslator]::FromHtml('#11243A');$l.ForeColor=[Drawing.Color]::White;for($i=0;$i -lt $Columns.Length;$i++){[void]$l.Columns.Add($Columns[$i],$Widths[$i])};return $l}
$root=[Windows.Forms.TableLayoutPanel]::new();$root.Dock='Fill';$root.Padding=[Windows.Forms.Padding]::new(12);$root.ColumnCount=1;$root.RowCount=4;[void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',96));[void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',104));[void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',100));[void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',38));$ui.Form.Controls.Add($root)
$header=[Windows.Forms.FlowLayoutPanel]::new();$header.Dock='Fill';$header.WrapContents=$true
$title=New-ConsoleLabel '校园应急信息发布与疏散指挥';$title.Font=[Drawing.Font]::new('Microsoft YaHei',15,[Drawing.FontStyle]::Bold);$title.Width=370;$title.AutoSize=$false;$title.Height=40;$header.Controls.Add($title)
$header.Controls.Add((New-ConsoleLabel 'B板 CH340：'));$ui.Ports=[Windows.Forms.ComboBox]::new();$ui.Ports.Width=120;$ui.Ports.DropDownStyle='DropDownList';$ui.Ports.Margin=[Windows.Forms.Padding]::new(4,8,4,4);$header.Controls.Add($ui.Ports)
$ui.Refresh=New-ConsoleButton '刷新端口' 90;$header.Controls.Add($ui.Refresh);$ui.Connect=New-ConsoleButton '连接' 90;$header.Controls.Add($ui.Connect)
$ui.Repair=New-ConsoleButton '修复串口' 100;$header.Controls.Add($ui.Repair)
$ui.AutoConnect=[Windows.Forms.CheckBox]::new();$ui.AutoConnect.Text='自动连接 / 断线重连';$ui.AutoConnect.Checked=$true;$ui.AutoConnect.AutoSize=$true;$ui.AutoConnect.Margin=[Windows.Forms.Padding]::new(5,10,5,4);$header.Controls.Add($ui.AutoConnect)
$tip=New-ConsoleLabel '115200 / 8N1 · 自动等待B板上电；CH340代码10定向修复；主动断开后停止重连。';$tip.Width=1050;$tip.AutoSize=$false;$header.Controls.Add($tip);$root.Controls.Add($header,0,0)
$cards=[Windows.Forms.TableLayoutPanel]::new();$cards.Dock='Fill';$cards.ColumnCount=5
foreach($cardName in @('连接状态','板端实际事件','当前疏散路线','请求确认','探头温度')){[void]$cards.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',20));$g=New-ConsoleGroup $cardName;$v=[Windows.Forms.Label]::new();$v.Dock='Fill';$v.Text='尚未连接';$v.Font=[Drawing.Font]::new('Microsoft YaHei',10,[Drawing.FontStyle]::Bold);$v.TextAlign='MiddleLeft';$g.Controls.Add($v);$cards.Controls.Add($g);$ui[$cardName]=$v};$root.Controls.Add($cards,0,1)
$tabs=[Windows.Forms.TabControl]::new();$tabs.Dock='Fill';$root.Controls.Add($tabs,0,2)
$overview=[Windows.Forms.TabPage]::new('应急控制与信息发布');$overview.BackColor=$ui.Form.BackColor;$overview.ForeColor=$ui.Form.ForeColor;$tabs.TabPages.Add($overview)
$layout=[Windows.Forms.TableLayoutPanel]::new();$layout.Dock='Fill';$layout.ColumnCount=2;[void]$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',41));[void]$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',59));$overview.Controls.Add($layout)
$left=New-ConsoleGroup '人工事件与封路预案';$layout.Controls.Add($left,0,0)
$controls=[Windows.Forms.FlowLayoutPanel]::new();$controls.Dock='Fill';$controls.FlowDirection='TopDown';$controls.WrapContents=$false;$controls.AutoScroll=$true;$left.Controls.Add($controls)
$eventRow=[Windows.Forms.FlowLayoutPanel]::new();$eventRow.Width=390;$eventRow.Height=88
$ui.EventButtons=@()
foreach($pair in @(@('火灾应急','DEMO FIRE'),@('地震应急','DEMO QUAKE'),@('实验室事故','DEMO LAB'),@('启动演练','DEMO DRILL'))){$b=New-ConsoleButton $pair[0] 170;$b.Tag=$pair[1];$b.Add_Click({param($sender,$eventArgs) Invoke-ConsoleUI {$script:consoleSession.Request([string]$sender.Tag)|Out-Null}});$eventRow.Controls.Add($b);$ui.EventButtons+=,$b};$controls.Controls.Add($eventRow)
$ui.Stop=New-ConsoleButton '请求解除应急 / 恢复轮播' 350;$ui.Stop.Add_Click({Invoke-ConsoleUI {$script:consoleSession.Request('DEMO STOP')|Out-Null}});$controls.Controls.Add($ui.Stop)
$ui.TempClear=New-ConsoleButton '人工解除温度锁存' 350;$ui.TempClear.Add_Click({Invoke-ConsoleUI {$script:consoleSession.ClearTemperatureAlarm()|Out-Null}});$controls.Controls.Add($ui.TempClear)
$note=New-ConsoleLabel '高温锁存须先降温确认并人工解除，再请求退出应急；A本地告警保留原权限。';$note.AutoSize=$false;$note.Width=370;$note.Height=47;$controls.Controls.Add($note)
$controls.Controls.Add((New-ConsoleLabel '附加封路预案（事件危险边仍由FPGA处理）'))
$barRow=[Windows.Forms.FlowLayoutPanel]::new();$barRow.Width=390;$barRow.Height=44
$ui.Barrier=[Windows.Forms.ComboBox]::new();$ui.Barrier.Width=230;$ui.Barrier.DropDownStyle='DropDownList';$ui.Barrier.Margin=[Windows.Forms.Padding]::new(5,8,5,4);[void]$ui.Barrier.Items.AddRange(@('0 · 无附加封路','1 · 增加一处封路','2 · 增加两处封路','3 · 四出口关闭预案'));$ui.Barrier.SelectedIndex=0;$barRow.Controls.Add($ui.Barrier)
$ui.Apply=New-ConsoleButton '应用预案' 110;$ui.Apply.Add_Click({Invoke-ConsoleUI {$script:consoleSession.Request('BARRIER SET '+$ui.Barrier.SelectedIndex)|Out-Null}});$barRow.Controls.Add($ui.Apply);$controls.Controls.Add($barRow)
$ui.RouteDetail=New-ConsoleLabel '等待新鲜路线状态。';$ui.RouteDetail.AutoSize=$false;$ui.RouteDetail.Width=365;$ui.RouteDetail.Height=104;$controls.Controls.Add($ui.RouteDetail)
$ui.Drill=New-ConsoleLabel '演练观察计时：未开始';$ui.Drill.AutoSize=$false;$ui.Drill.Width=365;$ui.Drill.Height=44;$controls.Controls.Add($ui.Drill)
$right=New-ConsoleGroup '字幕发布与状态联动';$layout.Controls.Add($right,1,0)
$pub=[Windows.Forms.FlowLayoutPanel]::new();$pub.Dock='Fill';$pub.FlowDirection='TopDown';$pub.WrapContents=$false;$pub.AutoScroll=$true;$right.Controls.Add($pub)
$ui.Auto=[Windows.Forms.CheckBox]::new();$ui.Auto.Text='根据板端实际状态自动发布应急字幕';$ui.Auto.Checked=$true;$ui.Auto.AutoSize=$true;$ui.Auto.Margin=[Windows.Forms.Padding]::new(5,8,5,8);$ui.Auto.Add_CheckedChanged({if($script:consoleSession){$script:consoleSession.SetAutomatic($ui.Auto.Checked)}});$pub.Controls.Add($ui.Auto)
$ui.AutoText=New-ConsoleLabel '联动依据：连接后读取实际事件和路线。';$ui.AutoText.AutoSize=$false;$ui.AutoText.Width=545;$ui.AutoText.Height=66;$pub.Controls.Add($ui.AutoText)
$pub.Controls.Add((New-ConsoleLabel '自定义正文（单行；应急联动开启时优先保护应急通知）'))
$ui.Caption=[Windows.Forms.TextBox]::new();$ui.Caption.Width=545;$ui.Caption.MaxLength=256;$ui.Caption.Font=[Drawing.Font]::new('Microsoft YaHei',11);$ui.Caption.Margin=[Windows.Forms.Padding]::new(5);$ui.Caption.Text='校园安全提示：请熟悉疏散路线，保持通道畅通。';$pub.Controls.Add($ui.Caption)
$pubRow=[Windows.Forms.FlowLayoutPanel]::new();$pubRow.Width=550;$pubRow.Height=45
$ui.Preview=New-ConsoleButton '预览' 90;$ui.Preview.Add_Click({Invoke-ConsoleUI {$image=[SubtitleCodec]::Raster($ui.Caption.Text);if($ui.Picture.Image){$ui.Picture.Image.Dispose()};$ui.Picture.Image=$image.Preview;$ui.Footer.Text='预览：'+$image.Width+'×16字模，显示放大2倍。'}});$pubRow.Controls.Add($ui.Preview)
$ui.Publish=New-ConsoleButton '发布正文' 110;$ui.Publish.Add_Click({Invoke-ConsoleUI {$script:consoleSession.Publish($ui.Caption.Text)|Out-Null}});$pubRow.Controls.Add($ui.Publish)
$ui.Clear=New-ConsoleButton '清除自定义字幕' 145;$ui.Clear.Add_Click({Invoke-ConsoleUI {$script:consoleSession.Clear()|Out-Null}});$pubRow.Controls.Add($ui.Clear);$pub.Controls.Add($pubRow)
$previewPanel=[Windows.Forms.Panel]::new();$previewPanel.Size=[Drawing.Size]::new(545,64);$previewPanel.AutoScroll=$true;$previewPanel.BackColor=[Drawing.Color]::FromArgb(18,56,90);$previewPanel.Margin=[Windows.Forms.Padding]::new(5);$ui.Picture=[Windows.Forms.PictureBox]::new();$ui.Picture.SizeMode='AutoSize';$previewPanel.Controls.Add($ui.Picture);$pub.Controls.Add($previewPanel)
$ui.Progress=[Windows.Forms.ProgressBar]::new();$ui.Progress.Width=545;$ui.Progress.Maximum=128;$ui.Progress.Margin=[Windows.Forms.Padding]::new(5,12,5,5);$pub.Controls.Add($ui.Progress)
$ui.Operation=New-ConsoleLabel '尚未发送。完整字幕经CRC及A板VS提交后才返回成功。';$ui.Operation.AutoSize=$false;$ui.Operation.Width=545;$ui.Operation.Height=80;$pub.Controls.Add($ui.Operation)
$logTab=[Windows.Forms.TabPage]::new('板端事件快照');$logTab.BackColor=$ui.Form.BackColor;$logTab.ForeColor=$ui.Form.ForeColor;$tabs.TabPages.Add($logTab)
$logBar=[Windows.Forms.FlowLayoutPanel]::new();$logBar.Dock='Top';$logBar.Height=58
$ui.ReadLog=New-ConsoleButton '读取最近64条' 135;$ui.ReadLog.Add_Click({Invoke-ConsoleUI {$script:consoleSession.ReadLog()|Out-Null}});$logBar.Controls.Add($ui.ReadLog)
$ui.ExportBoard=New-ConsoleButton '导出完整快照CSV' 160;$logBar.Controls.Add($ui.ExportBoard)
$ui.ClearLog=New-ConsoleButton '清空板端日志' 135;$ui.ClearLog.Add_Click({Invoke-ConsoleUI {$script:consoleSession.ClearLog()|Out-Null}});$logBar.Controls.Add($ui.ClearLog)
$logBar.Controls.Add((New-ConsoleLabel '板端MS为上电毫秒；电脑接收时间不是事件发生时间。'))
$ui.BoardList=New-ConsoleList @('接收时间','板端毫秒','事件','CTX HEX','DATA HEX') @(230,120,300,120,120);$logTab.Controls.Add($ui.BoardList);$logTab.Controls.Add($logBar)
$auditTab=[Windows.Forms.TabPage]::new('电脑操作记录');$auditTab.BackColor=$ui.Form.BackColor;$auditTab.ForeColor=$ui.Form.ForeColor;$tabs.TabPages.Add($auditTab)
$auditBar=[Windows.Forms.FlowLayoutPanel]::new();$auditBar.Dock='Top';$auditBar.Height=55;$ui.ExportAudit=New-ConsoleButton '导出电脑记录CSV' 165;$auditBar.Controls.Add($ui.ExportAudit);$auditBar.Controls.Add((New-ConsoleLabel '记录请求、确认、字幕和连接变化；最多4096条，覆盖数量显示在诊断页。'))
$ui.AuditList=New-ConsoleList @('电脑接收时间','类别','内容') @(210,140,720);$auditTab.Controls.Add($ui.AuditList);$auditTab.Controls.Add($auditBar)
$diagTab=[Windows.Forms.TabPage]::new('状态诊断');$diagTab.BackColor=$ui.Form.BackColor;$diagTab.ForeColor=$ui.Form.ForeColor;$tabs.TabPages.Add($diagTab)
$ui.Diagnostic=[Windows.Forms.TextBox]::new();$ui.Diagnostic.Multiline=$true;$ui.Diagnostic.ReadOnly=$true;$ui.Diagnostic.Dock='Fill';$ui.Diagnostic.ScrollBars='Vertical';$ui.Diagnostic.BackColor=[Drawing.ColorTranslator]::FromHtml('#11243A');$ui.Diagnostic.ForeColor=[Drawing.Color]::White;$ui.Diagnostic.Font=[Drawing.Font]::new('Consolas',11);$diagTab.Controls.Add($ui.Diagnostic)
$ui.Footer=New-ConsoleLabel '未连接。连接后先核对PING和完整状态；地图与寻路由FPGA完成。';$ui.Footer.Dock='Fill';$root.Controls.Add($ui.Footer,0,3)
# Discovery and repair run on a background thread; UI only reads immutable snapshots.
$script:portMonitor=[EmergencyConsole.PortMonitor]::new()
$script:recoveryClock=[Diagnostics.Stopwatch]::StartNew()
$script:portRevision=-1;$script:portState=$null;$script:preferredId='';$script:targetPort='';$script:attemptPort='';$script:attemptId='';$script:retryAt=0L;$script:failures=0;$script:wasRunning=$false;$script:remembered=$false;$script:recoveryText='等待检测B板CH340。';$script:lastRecoveryText='';$script:repairProcess=$null
$script:settingsFile=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'HX4S20CConsole/connection.json'
if(!$NoShow){try{if(Test-Path -LiteralPath $script:settingsFile){$saved=Get-Content -LiteralPath $script:settingsFile -Raw|ConvertFrom-Json;if($saved.deviceId -like 'USB\VID_1A86&PID_7523\*'){$script:preferredId=[string]$saved.deviceId}}}catch{}}
function Update-ConsolePortList {
 $script:portState=$script:portMonitor.ReadView()
 if($script:portState.Revision -eq $script:portRevision){return}
 $script:portRevision=$script:portState.Revision
 $old=[string]$ui.Ports.SelectedItem
 $names=@($script:portState.Ports)
 if(($names -join ',') -ne (@($ui.Ports.Items) -join ',')){
  $ui.Ports.BeginUpdate();try{$ui.Ports.Items.Clear();foreach($name in $names){[void]$ui.Ports.Items.Add($name)}
   if($names -contains $old){$ui.Ports.SelectedItem=$old}else{$target=[EmergencyConsole.RecoveryPolicy]::Target($script:portState,$script:preferredId,'');if($target -and $names -contains $target.Port){$ui.Ports.SelectedItem=$target.Port}}
  }finally{$ui.Ports.EndUpdate()}
 }
}
function Start-ConsoleConnection([string]$PortName) {
 if($script:consoleSession -and $script:consoleSession.ReadView().Running){return}
 if($script:portMonitor.ReadView().Repairing -or ($script:repairProcess -and !$script:repairProcess.HasExited)){$script:recoveryText='等待CH340修复完成后再连接。';return}
 $previous=$script:consoleSession
 if($previous){foreach($notice in $previous.DrainNotices()){Add-ConsoleRow $ui.AuditList @((Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$notice.Kind,$notice.Text)}}
 $script:consoleSession=New-ConsoleSession $PortName
 if($previous){$script:consoleSession.InheritAudit($previous);$previous.Dispose()}
 $script:consoleSession.SetAutomatic($ui.Auto.Checked)
 $script:attemptPort=$PortName;$d=[EmergencyConsole.RecoveryPolicy]::Target($script:portState,'',$PortName);$script:attemptId=$(if($d){$d.Id}else{''})
 if($d){$script:preferredId=$d.Id;$script:targetPort=''}
 $script:remembered=$false;$script:lastBoardLogRevision=-1;$script:wasRunning=$true
 $script:consoleSession.Start();$script:recoveryText='正在连接 '+$PortName+'，重新核对PING及完整状态……'
}
function Update-ConsoleConnection {
 if($script:repairProcess -and $script:repairProcess.HasExited){
  $message='管理员修复进程已结束，请核对设备状态。'
  try{$repairResult=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $script:settingsFile) 'last-repair.json') -Raw|ConvertFrom-Json;$message=[string]$repairResult.message}catch{}
  $script:repairProcess.Dispose();$script:repairProcess=$null;$script:portMonitor.CompleteExternalRepair($message);$script:recoveryText=$message
 }
 Update-ConsolePortList
 $view=$(if($script:consoleSession){$script:consoleSession.ReadView()}else{$null})
 $running=$view -and $view.Running
 if($view -and $view.Healthy){
  $script:failures=0
  if(!$script:remembered){$script:remembered=$true
   if($script:attemptId){$script:preferredId=$script:attemptId
    if(!$NoShow){try{[void][IO.Directory]::CreateDirectory((Split-Path -Parent $script:settingsFile));@{deviceId=$script:preferredId;port=$script:attemptPort}|ConvertTo-Json|Set-Content -LiteralPath $script:settingsFile -Encoding UTF8}catch{}}
   }
  }
  $script:recoveryText='串口状态有效：'+$script:attemptPort
 }
 if($script:wasRunning -and !$running){
  $script:wasRunning=$false;$script:failures++;$script:retryAt=$script:recoveryClock.ElapsedMilliseconds+[EmergencyConsole.RecoveryPolicy]::RetryDelay($script:failures)
  $script:recoveryText=$(if(!$ui.AutoConnect.Checked){'已停止自动连接；点击连接或勾选自动连接恢复。'}elseif($view.FailureKind -eq 'ACCESS'){'串口被其他程序占用或访问被拒绝；关闭旧控制台/串口助手后自动重试。'}else{'连接中断，等待端口恢复后重新核验；旧控制请求不会重发。'})
 }
 $repairBusy=$script:portState.Repairing -or ($script:repairProcess -and !$script:repairProcess.HasExited)
 $ui.Repair.Enabled=!$running -and !$repairBusy
 $ui.Connect.Enabled=!$repairBusy
 $ui.Repair.Text=$(if($script:portState.NeedsElevation){'管理员修复'}else{'修复串口'})
 if($running -or ($NoShow -and !$EnableRecoveryTests)){return}
 if(!$ui.AutoConnect.Checked){return}
 if($script:portState.Error){$script:recoveryText=$script:portState.Error;return}
 $target=[EmergencyConsole.RecoveryPolicy]::Target($script:portState,$script:preferredId,$script:targetPort)
 if($repairBusy){$script:recoveryText='正在修复CH340，等待USB重新枚举……';return}
 if(!$target){$script:recoveryText=$(if($script:portState.Devices.Count -eq 0){'等待B板USB串口；请确认已连接USB数据线。'}else{'请在端口列表选择B板，然后点击连接。'});return}
 if([EmergencyConsole.RecoveryPolicy]::CanAutoRepair($target,$false)){
  [void]$script:portMonitor.RequestRepair($target.Id,$false,$false);$script:recoveryText=$script:portState.RepairMessage;return
 }
 if($target.Problem -ne 0){$script:recoveryText='CH340设备错误码 '+$target.Problem+'；'+$script:portState.RepairMessage;return}
 if($script:recoveryClock.ElapsedMilliseconds -lt $script:retryAt){return}
 if($script:portState.Ports -contains $target.Port){Start-ConsoleConnection $target.Port}else{$script:recoveryText='CH340正在初始化，等待COM端口出现。'}
}
$ui.Refresh.Add_Click({$script:portMonitor.Refresh();Update-ConsolePortList})
$ui.AutoConnect.Add_CheckedChanged({if($ui.AutoConnect.Checked){$script:retryAt=0;$script:targetPort='';$script:portMonitor.Refresh()}else{if(!$script:consoleSession -or !$script:consoleSession.ReadView().Running){$script:recoveryText='自动连接已关闭。'}}})
$ui.Connect.Add_Click({Invoke-ConsoleUI {
 if($script:consoleSession -and $script:consoleSession.ReadView().Running){$ui.AutoConnect.Checked=$false;$script:consoleSession.Stop();$ui.Footer.Text='正在断开，自动重连已停止；不会发送STOP或清除字幕。';return}
 if(!$ui.Ports.SelectedItem){$script:portMonitor.Refresh();$script:recoveryText='正在等待串口；可使用修复串口处理CH340故障。';return}
 $script:targetPort=[string]$ui.Ports.SelectedItem;$script:retryAt=0;Start-ConsoleConnection $script:targetPort
}})
$ui.Repair.Add_Click({Invoke-ConsoleUI {
 $running=$script:consoleSession -and $script:consoleSession.ReadView().Running
 if($running){throw '请先断开当前串口，再修复设备。'}
 $target=[EmergencyConsole.RecoveryPolicy]::Target($script:portState,$script:preferredId,[string]$ui.Ports.SelectedItem)
 if(!$target){$script:portMonitor.Refresh();$ui.Footer.Text='未确定B板CH340；请先接USB数据线，多个设备时先选择B板端口。';return}
 if([EmergencyConsole.WindowsDeviceBackend]::IsAdministrator()){[void]$script:portMonitor.RequestRepair($target.Id,$true,$false)}else{
  # UAC is requested only by this explicit button, never from a retry loop.
  $helper=Join-Path $PSScriptRoot 'repair_ch340.ps1'
  $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$helper+'" -InstanceId "'+$target.Id+'"'
  $script:repairProcess=Start-Process -FilePath "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
 }
 $script:retryAt=$script:recoveryClock.ElapsedMilliseconds+2000;$ui.Footer.Text='已请求定向修复CH340；完成后勾选自动连接即可继续。'
}})
function Export-ConsoleFile([bool]$Board){
 if(!$script:consoleSession){throw '尚无会话记录。'}
 $dialog=[Windows.Forms.SaveFileDialog]::new();$dialog.Filter='CSV文件 (*.csv)|*.csv';$dialog.FileName=$(if($Board){'板端事件快照.csv'}else{'电脑操作记录.csv'})
 try{if($dialog.ShowDialog($ui.Form) -eq 'OK'){if($Board){$script:consoleSession.ExportBoardLog($dialog.FileName)}else{$script:consoleSession.ExportAudit($dialog.FileName)};$ui.Footer.Text='已导出：'+$dialog.FileName}}finally{$dialog.Dispose()}
}
$ui.ExportAudit.Add_Click({Invoke-ConsoleUI {Export-ConsoleFile $false}});$ui.ExportBoard.Add_Click({Invoke-ConsoleUI {Export-ConsoleFile $true}})
. (Join-Path $PSScriptRoot 'demo_dashboard.ps1')
$ui.Timer=[Windows.Forms.Timer]::new();$ui.Timer.Interval=100
$ui.Timer.Add_Tick({
 Update-ConsoleConnection
 $ui.Footer.Text=$script:recoveryText
 if(!$script:consoleSession){$ui['连接状态'].Text=$script:recoveryText;Update-DemoDashboard $null;return}
 $view=$script:consoleSession.ReadView();$snapshot=$view.Status;$qualified=$view.Healthy -and $snapshot.Link -eq 1
 $ui.Connect.Text=$(if($view.Running){'断开'}else{'连接'});$ui.Refresh.Enabled=$true;$ui.Ports.Enabled=!$view.Running
 $ui['连接状态'].Text=$(if(!$view.Running){$script:recoveryText}elseif(!$view.Healthy){'等待串口有效状态'}elseif($snapshot.Link -eq 1){'串口就绪 / 双板在线'}else{'串口就绪 / 双板离线'})
 $ui['探头温度'].Text=$(if($view.Healthy){[EmergencyConsole.Policy]::TemperatureText($snapshot)}else{'温度状态未知 / 串口未就绪'});$ui['探头温度'].ForeColor=$(if($view.Healthy -and $snapshot.TempAlarm -eq 1){[Drawing.Color]::Coral}elseif($view.Healthy -and $snapshot.TempValid -eq 1){[Drawing.Color]::LightGreen}else{[Drawing.Color]::Khaki})
 $ui['板端实际事件'].Text=$(if($qualified){[EmergencyConsole.Policy]::EventName($snapshot.Act)}else{'未知 / 历史值失效'})
 $ui['当前疏散路线'].Text=$(if(!$qualified){'暂无有效路线状态'}elseif(!$snapshot.Emergency){'正常轮播'}elseif(!$snapshot.RouteQualified -or $view.RequestPending){'路线确认或更新中'}elseif($snapshot.Exit -eq 0 -or $snapshot.Route -eq 0){'未返回可用路线'}else{[EmergencyConsole.Policy]::ExitName($snapshot.Exit)})
 $ui['板端实际事件'].ForeColor=$(if($qualified -and $snapshot.Emergency){[Drawing.Color]::Coral}else{[Drawing.Color]::LightCyan});$ui['请求确认'].Text=$view.Action;$ui['当前疏散路线'].ForeColor=$(if($qualified -and $snapshot.RouteQualified -and !$view.RequestPending -and $snapshot.Exit -gt 0 -and $snapshot.Route -gt 0){[Drawing.Color]::LightGreen}else{[Drawing.Color]::Khaki})
 foreach($eventButton in $ui.EventButtons){$eventButton.Enabled=$qualified -and $snapshot.TempAlarm -ne 1};$ui.Stop.Enabled=$qualified -and $snapshot.TempAlarm -ne 1;$ui.TempClear.Enabled=$view.Healthy -and $snapshot.SensorInstalled -and $snapshot.TempAlarm -eq 1 -and $snapshot.TempClearAllowed -eq 1;$ui.Apply.Enabled=$qualified -and $snapshot.Emergency;$ui.Barrier.Enabled=$ui.Apply.Enabled
 $manualAllowed=$qualified -and !($view.Auto -and ($snapshot.Emergency -or $snapshot.TempAlarm -eq 1 -or $snapshot.TempWarn -eq 1));$ui.Publish.Enabled=$manualAllowed;$ui.Clear.Enabled=$manualAllowed;$ui.ReadLog.Enabled=$view.Healthy;$ui.ClearLog.Enabled=$view.Healthy;$ui.ExportAudit.Enabled=$true;$ui.ExportBoard.Enabled=$view.BoardLogRevision -gt 0
 $ui.Operation.Text=$view.Operation;$ui.Progress.Value=[Math]::Min(128,[Math]::Max(0,$view.Progress));$ui.Drill.Text='电脑演练观察计时：'+$view.Drill
 $ui.RouteDetail.Text=$(if($qualified){'板端封路请求：'+[EmergencyConsole.Policy]::BarrierName($snapshot.Bar)+"`r`n"+$(if($view.RequestPending){'请求等待板端确认，暂不推荐出口。'}else{[EmergencyConsole.Policy]::RouteText($snapshot)})}else{'未收到有效双板状态；历史出口不作为当前推荐。'})
 $automaticText=$(if($qualified){$view.AutoCaption}else{$null});$ui.AutoText.Text=$(if($automaticText){$(if($view.Auto){'当前联动模板：'}else{'自动联动已关闭；状态参考：'})+$automaticText}else{'当前没有可发布的应急模板；断链时显示器可能仍保留最后字幕。'})
 $ui.Diagnostic.Text=$script:recoveryText+"`r`n"+$script:portState.RepairMessage+"`r`n"+$view.LastError+"`r`n`r`n"+$(if($snapshot){$snapshot.Raw+"`r`n`r`n"}else{''})+"ACK/APPLY仅证明协议与状态吻合，不等于HDMI完整显示。`r`nPHY是配置状态；CACHE不证明TF当前在位或健康。`r`nDS18B20原始数以1/16℃上传；仅TV=1为当前有效温度；掉线不清锁存。`r`nREV是路线签名变化，不是人员数量或求解器执行次数。`r`n电脑记录覆盖条数："+$view.AuditLost
 if($view.BoardLogRevision -ne $script:lastBoardLogRevision){$ui.BoardList.Items.Clear();foreach($row in $script:consoleSession.BoardLog()){Add-ConsoleRow $ui.BoardList @($row.ReceivedAt,$row.Ms,$row.Description,$row.Context,$row.Data)};$script:lastBoardLogRevision=$view.BoardLogRevision}
 Update-DemoDashboard $view
 foreach($notice in $script:consoleSession.DrainNotices()){Add-ConsoleRow $ui.AuditList @((Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$notice.Kind,$notice.Text);if($ui.AuditList.Items.Count -gt 400){$ui.AuditList.Items.RemoveAt(0)};$ui.Footer.Text=$notice.Text}
})
$ui.Form.Add_FormClosed({$ui.Timer.Stop();$ui.Timer.Dispose();$script:portMonitor.Dispose();if($script:consoleSession){$script:consoleSession.Dispose()};if($ui.Picture.Image){$ui.Picture.Image.Dispose()}})
foreach($initialControl in (@($ui.EventButtons)+@($ui.Stop,$ui.TempClear,$ui.Apply,$ui.Barrier,$ui.Publish,$ui.Clear,$ui.ReadLog,$ui.ClearLog,$ui.ExportBoard,$ui.ExportAudit))){$initialControl.Enabled=$false}
if(!$NoShow){$script:portMonitor.Start()};$ui.Timer.Start()
if(!$NoShow){[void]$ui.Form.ShowDialog()}
