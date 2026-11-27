# Presentation helpers never enqueue hardware commands. Only explicit action buttons
# delegate to the existing guarded controls and the sole serial Session owner.
$script:demoWatch=[Diagnostics.Stopwatch]::new();$script:demoStage=0;$script:demoLimit=180;$script:demoFullscreen=$false
$script:demoSteps=@(
 @{Title='基础播放';Short='01  基础要求';Say='系统基于HX4S20C双板FPGA。通过SPI读取TF卡中的24位BMP，解析后写入SDRAM，再由HDMI稳定输出；支持手动切图、3/5/8秒轮播、暂停和48kHz音频输出。';Do='指向HDMI画面；按一次切图，再展示自动轮播。声音提前打开，用一句话说明音视频同时输出。';See='观察图片连续显示与声音。上电、读卡和串口准备在讲解计时前完成。';Caption='TF读图 · HDMI音视频 · 稳定轮播'}
 @{Title='画面增强';Short='02  拓展效果';Say='在基础播放上，系统加入平滑转场、图片缩放适配、实时亮度与对比度调节、文字叠加、音源选择和音频可视化。粒子场景进出也具有过渡效果。';Do='用原有拨码/按键展示翻牌或缩放；切入、切出粒子画面；再调整一次亮度或对比度，指向音频可视化。';See='只演示一组代表效果，其他效果口述覆盖，减少重复拨码。';Caption='平滑转场 · 缩放适配 · 音频可视化'}
 @{Title='应急寻路';Short='03  自主创新';Say='系统将多媒体展示与校园应急引导结合，支持四类事件、立体地图、建筑中文名称、最短可达路径、三档地图缩放和持续跟随镜头。增加路障后可重新规划出口与路线。';Do='点击“手动火灾演示”；等待实际事件和出口确认，再点“增加封路”，展示路线变化。演示后，在未温度锁存时请求恢复轮播并确认，再介绍温度。';See='推荐出口必须等新状态确认；无路时如实显示暂无可用路线。地震、实验室事故和演练用一句话说明。';Caption='校园应急引导 · 动态寻路 · 路障重规划'}
 @{Title='温度自动联动';Short='04  温度联动';Say='DS18B20实时测温并叠加到HDMI左上角。45℃预警，一次有效采样达到55℃即锁存并请求火灾预案，板端工作不依赖电脑。故障不会清除已有报警。';Do='接好探头后展示实时读数；达到真实阈值时观察自动告警。降到50℃及以下并满足三次有效采样后，先人工解除温度锁存，再独立请求恢复轮播，确认正常后再演示串口自定义字幕。';See='升温和降温需要实际时间；三分钟版可展示读数并说明阈值。手动火灾按钮始终标明人工演示。';Caption='实时测温｜45℃预警 · 55℃自动报警'}
 @{Title='串口信息发布';Short='05  串口交互';Say='最后，电脑通过B板USB串口发送中英文正文。FPGA完成完整字模校验后，在帧边界更新HDMI滚动字幕，同时返回状态与事件记录；控制台还支持日志导出与串口自动恢复。';Do='确认已恢复正常且无温度锁存后，点击右侧“发布本段HDMI字幕”，指向HDMI字幕，再指出上方连接与实际状态。';See='若温度告警尚未解除，展示串口状态、日志和自动应急字幕，不覆盖告警。';Caption='串口实时发布｜你好，FPGA！HELLO HDMI'}
 @{Title='收束与亮点';Short='06  总结收束';Say='我们的创新在于将展示、环境感知、自动应急、动态疏散和电脑信息发布整合为以太网双板协作的纯FPGA系统，并通过状态确认、故障保锁和串口恢复提升演示可靠性。';Do='概括展示、感知、应急、引导与信息发布的闭环，结束演示。';See='突出一条闭环：正常展示 → 事件触发 → 地图引导 → 路障重规划 → 状态记录。';Caption='展示 · 感知 · 应急 · 引导 · 信息发布'}
)
function Get-DemoBudgets {if($script:demoLimit -eq 240){return @(30,40,60,50,35,25)};return @(25,30,45,35,25,20)}
function Get-DemoElapsed {return [int][Math]::Floor($script:demoWatch.Elapsed.TotalSeconds)}
function Format-DemoTime([int]$Seconds){return ('{0:00}:{1:00}' -f [int][Math]::Floor($Seconds/60),($Seconds%60))}
function Set-DemoStage([int]$Index){$script:demoStage=[Math]::Min(5,[Math]::Max(0,$Index));Update-DemoDashboard $(if($script:consoleSession){$script:consoleSession.ReadView()}else{$null})}
function Toggle-DemoClock {if($script:demoWatch.IsRunning){$script:demoWatch.Stop()}else{$script:demoWatch.Start()};Update-DemoDashboard $(if($script:consoleSession){$script:consoleSession.ReadView()}else{$null})}
function Set-DemoFullscreen([bool]$Enabled){
 if($Enabled -eq $script:demoFullscreen){return}
 $script:demoFullscreen=$Enabled
 if($Enabled){$script:demoRestoreBounds=$ui.Form.Bounds;$script:demoRestoreState=$ui.Form.WindowState;$ui.Form.WindowState='Normal';$ui.Form.FormBorderStyle='None';$ui.Form.WindowState='Maximized';$ui.Fullscreen.Text='退出全屏 F11'}
 else{$ui.Form.WindowState='Normal';$ui.Form.FormBorderStyle='Sizable';$ui.Form.Bounds=$script:demoRestoreBounds;$ui.Form.WindowState=$script:demoRestoreState;$ui.Fullscreen.Text='全屏 F11'}
}
function New-DemoText([string]$Text,[int]$Size=10){$label=[Windows.Forms.Label]::new();$label.Text=$Text;$label.Dock='Fill';$label.AutoSize=$false;$label.Font=[Drawing.Font]::new('Microsoft YaHei',$Size);$label.ForeColor=[Drawing.ColorTranslator]::FromHtml('#D8E9F5');$label.Padding=[Windows.Forms.Padding]::new(8);return $label}
$ui.DemoTab=[Windows.Forms.TabPage]::new('现场演示');$ui.DemoTab.BackColor=$ui.Form.BackColor;$ui.DemoTab.ForeColor=$ui.Form.ForeColor;$existingTabs=@($tabs.TabPages);$tabs.TabPages.Clear();[void]$tabs.TabPages.Add($ui.DemoTab);foreach($page in $existingTabs){[void]$tabs.TabPages.Add($page)};$tabs.SelectedIndex=0
$ui.DemoTabs=$tabs
$demoRoot=[Windows.Forms.TableLayoutPanel]::new();$demoRoot.Dock='Fill';$demoRoot.ColumnCount=1;$demoRoot.RowCount=3;$demoRoot.Padding=[Windows.Forms.Padding]::new(6)
[void]$demoRoot.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',58));[void]$demoRoot.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',100));[void]$demoRoot.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',44));$ui.DemoTab.Controls.Add($demoRoot)
$timeRow=[Windows.Forms.FlowLayoutPanel]::new();$timeRow.Dock='Fill';$timeRow.WrapContents=$false
$ui.DemoTime=New-DemoText '00:00 / 03:00' 21;$ui.DemoTime.Dock='None';$ui.DemoTime.Width=230;$ui.DemoTime.Height=51;$ui.DemoTime.Padding=[Windows.Forms.Padding]::new(4);$timeRow.Controls.Add($ui.DemoTime)
$ui.DemoMode=[Windows.Forms.ComboBox]::new();$ui.DemoMode.DropDownStyle='DropDownList';$ui.DemoMode.Width=150;$ui.DemoMode.Margin=[Windows.Forms.Padding]::new(8,13,8,4);[void]$ui.DemoMode.Items.AddRange(@('3分钟 · 精简演示','4分钟 · 完整讲解'));$ui.DemoMode.SelectedIndex=0
$ui.DemoMode.Add_SelectedIndexChanged({$script:demoLimit=$(if($ui.DemoMode.SelectedIndex -eq 1){240}else{180});Update-DemoDashboard $(if($script:consoleSession){$script:consoleSession.ReadView()}else{$null})});$timeRow.Controls.Add($ui.DemoMode)
$ui.DemoStart=New-ConsoleButton '开始计时 F5' 116;$ui.DemoStart.Margin=[Windows.Forms.Padding]::new(5,9,5,4);$ui.DemoStart.Add_Click({Toggle-DemoClock});$timeRow.Controls.Add($ui.DemoStart)
$ui.DemoReset=New-ConsoleButton '重新计时' 95;$ui.DemoReset.Margin=$ui.DemoStart.Margin;$ui.DemoReset.Add_Click({$script:demoWatch.Reset();Set-DemoStage 0});$timeRow.Controls.Add($ui.DemoReset)
$ui.Fullscreen=New-ConsoleButton '全屏 F11' 110;$ui.Fullscreen.Margin=$ui.DemoStart.Margin;$ui.Fullscreen.Add_Click({Set-DemoFullscreen (!$script:demoFullscreen)});$timeRow.Controls.Add($ui.Fullscreen)
$ui.DemoPhaseHint=New-DemoText '计时仅提醒，不自动发送控制命令。' 9;$ui.DemoPhaseHint.Dock='None';$ui.DemoPhaseHint.Width=250;$ui.DemoPhaseHint.Height=50;$timeRow.Controls.Add($ui.DemoPhaseHint);$demoRoot.Controls.Add($timeRow,0,0)
$body=[Windows.Forms.TableLayoutPanel]::new();$body.Dock='Fill';$body.ColumnCount=3
foreach($pct in @(22,51,27)){[void]$body.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',$pct))};$demoRoot.Controls.Add($body,0,1)
$nav=New-ConsoleGroup '演示顺序';$body.Controls.Add($nav,0,0);$navFlow=[Windows.Forms.TableLayoutPanel]::new();$navFlow.Dock='Fill';$navFlow.ColumnCount=1;$navFlow.RowCount=7
for($r=0;$r -lt 6;$r++){[void]$navFlow.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',12.5))};[void]$navFlow.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',25));$nav.Controls.Add($navFlow)
$ui.DemoStageButtons=@()
for($i=0;$i -lt 6;$i++){$b=New-ConsoleButton $script:demoSteps[$i].Short 180;$b.Dock='Fill';$b.Margin=[Windows.Forms.Padding]::new(2);$b.Tag=$i;$b.Add_Click({param($sender,$args) Set-DemoStage ([int]$sender.Tag)});$navFlow.Controls.Add($b,0,$i);$ui.DemoStageButtons+=,$b}
$ui.DemoReady=New-DemoText '等待连接' 9;$navFlow.Controls.Add($ui.DemoReady,0,6)
$cue=New-ConsoleGroup '讲解与操作提示';$body.Controls.Add($cue,1,0)
$cueGrid=[Windows.Forms.TableLayoutPanel]::new();$cueGrid.Dock='Fill';$cueGrid.ColumnCount=1;$cueGrid.RowCount=5
foreach($row in @(@('Absolute',40),@('Percent',34),@('Percent',34),@('Percent',20),@('Absolute',34))){[void]$cueGrid.RowStyles.Add([Windows.Forms.RowStyle]::new($row[0],[single]$row[1]))};$cue.Controls.Add($cueGrid)
$ui.DemoTitle=New-DemoText '' 16;$ui.DemoTitle.ForeColor=[Drawing.ColorTranslator]::FromHtml('#54D9E6');$cueGrid.Controls.Add($ui.DemoTitle,0,0)
$ui.DemoSay=New-DemoText '' 10;$cueGrid.Controls.Add($ui.DemoSay,0,1)
$ui.DemoDo=New-DemoText '' 10;$ui.DemoDo.ForeColor=[Drawing.ColorTranslator]::FromHtml('#A7E5CF');$cueGrid.Controls.Add($ui.DemoDo,0,2)
$ui.DemoSee=New-DemoText '' 9;$ui.DemoSee.ForeColor=[Drawing.ColorTranslator]::FromHtml('#C1D0E0');$cueGrid.Controls.Add($ui.DemoSee,0,3)
$ui.DemoCaption=New-DemoText '' 9;$ui.DemoCaption.ForeColor=[Drawing.ColorTranslator]::FromHtml('#90CDE9');$cueGrid.Controls.Add($ui.DemoCaption,0,4)
$actions=New-ConsoleGroup '现场快捷操作';$body.Controls.Add($actions,2,0)
$actionGrid=[Windows.Forms.TableLayoutPanel]::new();$actionGrid.Dock='Fill';$actionGrid.ColumnCount=1;$actionGrid.RowCount=8
for($r=0;$r -lt 8;$r++){[void]$actionGrid.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',12.5))};$actions.Controls.Add($actionGrid)
$ui.DemoPublish=New-ConsoleButton '发布本段HDMI字幕' 230;$ui.DemoPublish.Dock='Fill';$ui.DemoPublish.Margin=[Windows.Forms.Padding]::new(3);$ui.DemoPublish.Add_Click({Invoke-ConsoleUI {if(!$ui.Publish.Enabled){throw '当前状态暂不允许普通字幕；请等待状态确认或使用原字幕页。'};$ui.Caption.Text=$script:demoSteps[$script:demoStage].Caption;$script:consoleSession.Publish($ui.Caption.Text)|Out-Null}});$actionGrid.Controls.Add($ui.DemoPublish,0,0)
$ui.DemoFire=New-ConsoleButton '手动火灾演示' 230;$ui.DemoFire.Dock='Fill';$ui.DemoFire.Margin=$ui.DemoPublish.Margin;$ui.DemoFire.BackColor=[Drawing.ColorTranslator]::FromHtml('#743341');$ui.DemoFire.Add_Click({if($ui.EventButtons[0].Enabled){Invoke-ConsoleUI {$script:consoleSession.Request('DEMO FIRE')|Out-Null}}});$actionGrid.Controls.Add($ui.DemoFire,0,1)
$ui.DemoBarrier=New-ConsoleButton '增加封路' 230;$ui.DemoBarrier.Dock='Fill';$ui.DemoBarrier.Margin=$ui.DemoPublish.Margin;$ui.DemoBarrier.Add_Click({if($ui.Apply.Enabled){$ui.Barrier.SelectedIndex=2;Invoke-ConsoleUI {$script:consoleSession.Request('BARRIER SET 2')|Out-Null}}});$actionGrid.Controls.Add($ui.DemoBarrier,0,2)
$ui.DemoOpen=New-ConsoleButton '恢复通行' 230;$ui.DemoOpen.Dock='Fill';$ui.DemoOpen.Margin=$ui.DemoPublish.Margin;$ui.DemoOpen.Add_Click({if($ui.Apply.Enabled){$ui.Barrier.SelectedIndex=0;Invoke-ConsoleUI {$script:consoleSession.Request('BARRIER SET 0')|Out-Null}}});$actionGrid.Controls.Add($ui.DemoOpen,0,3)
$ui.DemoTempClear=New-ConsoleButton '人工解除温度锁存' 230;$ui.DemoTempClear.Dock='Fill';$ui.DemoTempClear.Margin=$ui.DemoPublish.Margin;$ui.DemoTempClear.Add_Click({if($ui.TempClear.Enabled){Invoke-ConsoleUI {$script:consoleSession.ClearTemperatureAlarm()|Out-Null}}});$actionGrid.Controls.Add($ui.DemoTempClear,0,4)
$ui.DemoStop=New-ConsoleButton '请求恢复轮播' 230;$ui.DemoStop.Dock='Fill';$ui.DemoStop.Margin=$ui.DemoPublish.Margin;$ui.DemoStop.Add_Click({if($ui.Stop.Enabled){Invoke-ConsoleUI {$script:consoleSession.Request('DEMO STOP')|Out-Null}}});$actionGrid.Controls.Add($ui.DemoStop,0,5)
$ui.DemoLog=New-ConsoleButton '读取事件记录' 230;$ui.DemoLog.Dock='Fill';$ui.DemoLog.Margin=$ui.DemoPublish.Margin;$ui.DemoLog.Add_Click({if($ui.ReadLog.Enabled){Invoke-ConsoleUI {$script:consoleSession.ReadLog()|Out-Null};$tabs.SelectedTab=$logTab}});$actionGrid.Controls.Add($ui.DemoLog,0,6)
$ui.DemoAdvanced=New-ConsoleButton '全部控制 / 自定义字幕' 230;$ui.DemoAdvanced.Dock='Fill';$ui.DemoAdvanced.Margin=$ui.DemoPublish.Margin;$ui.DemoAdvanced.Add_Click({$tabs.SelectedTab=$overview});$actionGrid.Controls.Add($ui.DemoAdvanced,0,7)
$bottom=[Windows.Forms.TableLayoutPanel]::new();$bottom.Dock='Fill';$bottom.ColumnCount=3;[void]$bottom.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',118));[void]$bottom.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100));[void]$bottom.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',118))
$ui.DemoPrevious=New-ConsoleButton '上一步 ←' 110;$ui.DemoPrevious.Add_Click({Set-DemoStage ($script:demoStage-1)});$bottom.Controls.Add($ui.DemoPrevious,0,0)
$ui.DemoProgress=[Windows.Forms.ProgressBar]::new();$ui.DemoProgress.Dock='Fill';$ui.DemoProgress.Margin=[Windows.Forms.Padding]::new(12,14,12,12);$ui.DemoProgress.Maximum=180;$bottom.Controls.Add($ui.DemoProgress,1,0)
$ui.DemoNext=New-ConsoleButton '下一步 →' 110;$ui.DemoNext.Add_Click({Set-DemoStage ($script:demoStage+1)});$bottom.Controls.Add($ui.DemoNext,2,0);$demoRoot.Controls.Add($bottom,0,2)
$ui.Form.Add_KeyDown({param($sender,$e)
 if($e.KeyCode -eq 'F11'){Set-DemoFullscreen (!$script:demoFullscreen);$e.Handled=$true}
 elseif($e.KeyCode -eq 'Escape' -and $script:demoFullscreen){Set-DemoFullscreen $false;$e.Handled=$true}
 elseif($tabs.SelectedTab -eq $ui.DemoTab -and $e.KeyCode -eq 'F5'){Toggle-DemoClock;$e.Handled=$true}
 elseif($tabs.SelectedTab -eq $ui.DemoTab -and $e.KeyCode -eq 'Right'){Set-DemoStage ($script:demoStage+1);$e.Handled=$true}
 elseif($tabs.SelectedTab -eq $ui.DemoTab -and $e.KeyCode -eq 'Left'){Set-DemoStage ($script:demoStage-1);$e.Handled=$true}
})
function Update-DemoDashboard($View){
 $cueSize=$(if($ui.Form.ClientSize.Height -lt 760){9}else{10})
 foreach($label in @($ui.DemoSay,$ui.DemoDo)){if($label.Font.Size -ne $cueSize){$oldFont=$label.Font;$label.Font=[Drawing.Font]::new('Microsoft YaHei',$cueSize);$oldFont.Dispose()}}
 $step=$script:demoSteps[$script:demoStage];$budgets=Get-DemoBudgets;$start=0;for($i=0;$i -lt $script:demoStage;$i++){$start+=$budgets[$i]};$end=$start+$budgets[$script:demoStage]
 $elapsed=Get-DemoElapsed;$ui.DemoTime.Text=(Format-DemoTime $elapsed)+' / '+(Format-DemoTime $script:demoLimit)
 $ui.DemoTime.ForeColor=$(if($elapsed -ge $script:demoLimit){[Drawing.Color]::Coral}elseif($elapsed -ge $script:demoLimit-20){[Drawing.Color]::Khaki}else{[Drawing.ColorTranslator]::FromHtml('#54D9E6')})
 $ui.DemoStart.Text=$(if($script:demoWatch.IsRunning){'暂停计时 F5'}else{'开始计时 F5'})
 $ui.DemoProgress.Maximum=$script:demoLimit;$ui.DemoProgress.Value=[Math]::Min($script:demoLimit,[Math]::Max(0,$elapsed))
 $ui.DemoTitle.Text=$step.Title+'  '+(Format-DemoTime $start)+'–'+(Format-DemoTime $end)
 $ui.DemoSay.Text='讲解：'+$step.Say;$ui.DemoDo.Text='操作：'+$step.Do;$ui.DemoSee.Text='观察：'+$step.See;$ui.DemoCaption.Text='HDMI短字幕：'+$step.Caption
 $ui.DemoPhaseHint.Text=$(if($elapsed -ge $script:demoLimit){'已到目标时长，请完成收束。'}elseif($script:demoWatch.IsRunning -and $elapsed -ge $end -and $script:demoStage -lt 5){'本段建议用时已到，可进入下一步。'}else{'计时只提醒，操作由你手动触发。'})
 for($i=0;$i -lt 6;$i++){$ui.DemoStageButtons[$i].BackColor=$(if($i -eq $script:demoStage){[Drawing.ColorTranslator]::FromHtml('#14657B')}else{[Drawing.ColorTranslator]::FromHtml('#173B54')})}
 $ui.DemoPrevious.Enabled=$script:demoStage -gt 0;$ui.DemoNext.Enabled=$script:demoStage -lt 5
 $ready=$View -and $View.Healthy;$s=$(if($ready){$View.Status}else{$null});$online=$ready -and $s.Link -eq 1
 $ui.DemoReady.Text=$(if(!$ready){'串口：等待有效状态'}elseif(!$online){'串口：已连接；双板：离线'}else{'串口与双板：已就绪'})+"`r`n"+$(if($ready -and $s.SensorInstalled -and $s.TempValid -eq 1){'探头：有效实时温度'}else{'探头：未就绪 / 未接入'})
 $ui.DemoPublish.Enabled=$online -and $ui.Publish.Enabled -and !$View.Busy;$ui.DemoFire.Enabled=$online -and $ui.EventButtons[0].Enabled -and !$View.Busy
 $ui.DemoBarrier.Enabled=$online -and $ui.Apply.Enabled -and !$View.Busy;$ui.DemoOpen.Enabled=$ui.DemoBarrier.Enabled;$ui.DemoTempClear.Enabled=$ready -and $ui.TempClear.Enabled -and !$View.Busy;$ui.DemoStop.Enabled=$online -and $ui.Stop.Enabled -and !$View.Busy;$ui.DemoLog.Enabled=$ready -and $ui.ReadLog.Enabled -and !$View.Busy
}
foreach($key in @('板端实际事件','当前疏散路线','探头温度')){$ui[$key].Font=[Drawing.Font]::new('Microsoft YaHei',12,[Drawing.FontStyle]::Bold)}
# A fixed two-row header keeps discovery controls visible on1366x768 laptops.
$headerControls=@($header.Controls|Where-Object {$_ -ne $title -and $_ -ne $tip});$header.Controls.Clear()
$title.Width=420;$title.Height=32;$title.Margin=[Windows.Forms.Padding]::new(5,3,5,1);$header.Controls.Add($title)
$tip.Text='双板FPGA · HDMI信息发布 · 温度应急联动';$tip.Width=500;$tip.Height=28;$tip.Margin=[Windows.Forms.Padding]::new(5,7,5,0);$header.Controls.Add($tip);$header.SetFlowBreak($tip,$true)
foreach($control in $headerControls){$header.Controls.Add($control)}
$ui.Form.Add_Resize({Update-DemoDashboard $(if($script:consoleSession){$script:consoleSession.ReadView()}else{$null})})
Update-DemoDashboard $null
