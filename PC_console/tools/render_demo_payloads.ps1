$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot 'emergency_console_core.cs') -ReferencedAssemblies System.Drawing
$folder=Join-Path $package 'evidence/demo/hdmi'
[void][IO.Directory]::CreateDirectory($folder)
$rows=Get-Content -LiteralPath (Join-Path $package 'evidence/demo/caption-widths.json') -Raw|ConvertFrom-Json
$payloadLines=[Collections.Generic.List[string]]::new();$widths=[Collections.Generic.List[string]]::new();$index=0
foreach($row in $rows){
 $image=[SubtitleCodec]::Raster($row.text)
 try{
  [IO.File]::WriteAllBytes((Join-Path $folder ('bitmap'+$index+'.bin')),$image.Data)
  $widths.Add(('{0:x4}' -f $image.Width));$tag=[byte]($index+1);$digest=[SubtitleCodec]::Crc($image.Data,2048)
  $frames=[Collections.Generic.List[byte]]::new()
  for($packetIndex=0;$packetIndex -lt 130;$packetIndex++){
   if($packetIndex -eq 0){$packet=[SubtitleCodec]::Packet(0,$tag,$image.Width,0,$null)}
   elseif($packetIndex -eq 129){$packet=[SubtitleCodec]::Packet(2,$tag,128,$digest,$null)}
   else{$block=[byte[]]::new(16);[Array]::Copy($image.Data,($packetIndex-1)*16,$block,0,16);$packet=[SubtitleCodec]::Packet(1,$tag,($packetIndex-1),0,$block)}
   $frame=[SubtitleCodec]::Frame($packet);$frames.AddRange([byte[]]$frame)
   $hex=for($b=27;$b -ge 0;$b--){'{0:x2}' -f $packet[$b]};$payloadLines.Add(($hex -join ''))
  }
  [IO.File]::WriteAllBytes((Join-Path $folder ('caption'+$index+'.uart')),$frames.ToArray())
 }finally{$image.Preview.Dispose()}
 $index++
}
[IO.File]::WriteAllLines((Join-Path $folder 'packets.hex'),$payloadLines)
[IO.File]::WriteAllLines((Join-Path $folder 'widths.hex'),$widths)
Write-Output ('Rendered '+$index+' production-caption payloads, each130 CRC16 frames')
