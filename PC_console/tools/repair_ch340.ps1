param([Parameter(Mandatory=$true)][string]$InstanceId)
$ErrorActionPreference='Stop'
# Explicit UAC button only; no driver deletion, broad device reset, or forced reboot.
$folder=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'HX4S20CConsole'
[void][IO.Directory]::CreateDirectory($folder)
$result=@{at=[DateTimeOffset]::Now.ToString('o');instanceId=$InstanceId;success=$false;message=''}
try{
 Add-Type -Path (Join-Path $PSScriptRoot 'serial_recovery.cs') -ReferencedAssemblies System.Management
 if(!$InstanceId.StartsWith('USB\VID_1A86&PID_7523\',[StringComparison]::OrdinalIgnoreCase)){throw '目标不是B板CH340，未修复。'}
 $backend=[EmergencyConsole.WindowsDeviceBackend]::new()
 $result.message=$backend.Restart($InstanceId);$result.success=$true
}catch{$result.message=$_.Exception.Message}
$result|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $folder 'last-repair.json') -Encoding UTF8
if(!$result.success){exit 1}
