param([switch]$NoElevation)
$ErrorActionPreference='Stop'
$consoleScript=Join-Path $PSScriptRoot 'emergency_console.ps1'
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(!$NoElevation -and !$isAdmin){
 try{
  $arguments='-NoProfile -STA -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -NoElevation'
  Start-Process -FilePath "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" -Verb RunAs -WindowStyle Normal -ArgumentList $arguments
  exit
 }catch{
  # Cancelled UAC still permits ordinary discovery and connection.
 }
}
$created=$false;$mutex=[Threading.Mutex]::new($true,'Local\HX4S20CConsoleRecovery',[ref]$created)
try{
 if(!$created){Add-Type -AssemblyName System.Windows.Forms;[void][Windows.Forms.MessageBox]::Show('已有控制台在运行，请先关闭旧窗口，再启动现场演示版。','请先关闭旧控制台');return}
 & $consoleScript
}finally{if($created){$mutex.ReleaseMutex()};$mutex.Dispose()}
