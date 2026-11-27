param(
 [Parameter(Mandatory=$true)][string]$Port,
 [string]$Command='STATUS?',
 [string]$SaveTo
)
$ErrorActionPreference='Stop'
# Maintenance host only. The FPGA continues independently when disconnected.
if ($Command.Length -gt 16 -or $Command -match '[\r\n]') { throw 'One uppercase command, maximum 16 characters.' }
$serial=[System.IO.Ports.SerialPort]::new($Port,115200,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
$serial.Handshake=[System.IO.Ports.Handshake]::None
$serial.Encoding=[Text.Encoding]::ASCII
$serial.NewLine="`n"
$serial.ReadTimeout=1500
$serial.WriteTimeout=1500
$serial.DtrEnable=$false
$serial.RtsEnable=$false
try {
 $serial.Open()
 $serial.DiscardInBuffer()
 $serial.Write($Command+"`r`n")
 $export=$Command -match '^LOG READ (?:[1-9]|[1-5][0-9]|6[0-4])$'
 $lines=[Collections.Generic.List[string]]::new()
 for ($n=0;$n -lt 66;$n++) {
  $line=$serial.ReadLine().TrimEnd([char]13)
  $lines.Add($line)
  Write-Output $line
  if (!$export -or $line -eq 'END LOG' -or $line.StartsWith('ERR ')) { break }
 }
 if ($export -and $lines[$lines.Count-1] -ne 'END LOG' -and !$lines[$lines.Count-1].StartsWith('ERR ')) { throw 'Incomplete log export.' }
 if ($SaveTo) { [IO.File]::WriteAllLines([IO.Path]::GetFullPath($SaveTo),$lines,[Text.UTF8Encoding]::new($false)) }
} finally {
 if ($serial.IsOpen) { $serial.Close() }
 $serial.Dispose()
}
