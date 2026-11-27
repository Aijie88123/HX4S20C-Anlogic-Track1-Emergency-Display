param([ValidateSet('Synthesis','Route','All','Verify')][string]$Stage='All')
$ErrorActionPreference='Stop'
$projectRoot=$PSScriptRoot
$repoRoot=Split-Path $projectRoot
New-Item -ItemType Directory -Force -Path (Join-Path $repoRoot 'output') | Out-Null
$cli=$env:TD_CLI
if (!$cli) { $cli='D:/td_extract/5E781D7/bin/td_commands_prompt.exe' }
if (!(Test-Path -LiteralPath $cli)) { throw 'TD 2026.1 SP2 missing. Set TD_CLI to its td_commands_prompt.exe.' }
if ($cli -match '(^|[\\/])bin[\\/]td_commands_prompt.exe$' -and (Split-Path (Split-Path $cli)) -eq 'D:\') { throw 'D:/bin is the rejected old TD toolchain.' }
$flow=Join-Path $projectRoot 'DefaultFlow.tcl'
$evidence=Join-Path $repoRoot 'evidence/map_detail_20261020'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
function Get-SourceSnapshot {
    $paths=@()
    foreach ($dir in @('rtl','vendor','ip','constraints')) {
        if (Test-Path -LiteralPath (Join-Path $repoRoot $dir)) {
            $paths+=Get-ChildItem -LiteralPath (Join-Path $repoRoot $dir) -File -Recurse |
                Where-Object { $_.Extension -in @('.v','.vh','.sv','.sdc','.adc','.mem','.hex','.mif','.tcl','.xml','.cfg') } |
                Select-Object -ExpandProperty FullName
        }
    }
    $paths+=@('smart_terminal_720p.prj','syn_settings.cfg','phy_settings.cfg','DefaultFlow.tcl','parameter_initial_placement.adc') |
        ForEach-Object { Join-Path $projectRoot $_ }
    $rows=@($paths | Sort-Object -Unique | ForEach-Object {
        [ordered]@{path=$_.Substring($repoRoot.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}
    })
    return ConvertTo-Json -InputObject $rows -Depth 4 -Compress
}
$sourceSnapshot=Get-SourceSnapshot
$synManifest=Join-Path $evidence 'synthesis-source.json'
function Invoke-VerifiedStage([string]$Name,[string]$Settings,[string[]]$Steps) {
    $run=Join-Path $projectRoot "smart_terminal_Runs/$Name"
    New-Item -ItemType Directory -Force -Path $run | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot $Settings) -Destination (Join-Path $run 'settings.cfg')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'smart_terminal_720p.prj') -Destination (Join-Path $run 'smart_terminal.prj')
    if ($Name -eq 'phy_1') {
        Copy-Item -LiteralPath (Join-Path $projectRoot 'smart_terminal_Runs/syn_1/smart_terminal_rtl.db') -Destination (Join-Path $run 'smart_terminal_rtl.db')
    }
    $started=(Get-Date).ToUniversalTime()
    Push-Location $run
    try {
        # The CLI otherwise remains at its interactive prompt after source returns.
        $driver=Join-Path $run 'verified_driver.tcl'
        $driverText='if {[catch {source {__FLOW__}} result]} {puts stderr $result; exit 1}; exit 0'
        [IO.File]::WriteAllText($driver,$driverText.Replace('__FLOW__',$flow.Replace('\','/')))
        & $cli ($driver.Replace('\','/')) *> (Join-Path $evidence "$Name-build.log")
        $nativeExit=$LASTEXITCODE
    } finally { Pop-Location }
    if ($nativeExit -ne 0) { throw "$Name native return code $nativeExit" }
    foreach ($step in $Steps) {
        $end=Get-Item -LiteralPath (Join-Path $run ".$step.end.f") -ErrorAction SilentlyContinue
        $errorFile=Get-Item -LiteralPath (Join-Path $run ".$step.error.f") -ErrorAction SilentlyContinue
        if (!$end -or $end.LastWriteTimeUtc -lt $started) { throw "$Name did not finish $step in this run" }
        if ($errorFile -and $errorFile.LastWriteTimeUtc -ge $started) { throw "$Name failed $step; see $Name-build.log" }
    }
    Write-Output "$Name completed and fresh stage markers verified."
    return $started
}
if ($Stage -in @('Synthesis','All')) {
    $null=Invoke-VerifiedStage 'syn_1' 'syn_settings.cfg' @('read_design','opt_rtl','opt_gate')
    if ((Get-SourceSnapshot) -ne $sourceSnapshot) { throw 'Sources changed during synthesis. Rebuild before publishing.' }
    [IO.File]::WriteAllText($synManifest,$sourceSnapshot)
}
if ($Stage -in @('Route','All','Verify')) {
    if (!(Test-Path -LiteralPath $synManifest) -or [IO.File]::ReadAllText($synManifest) -ne $sourceSnapshot) {
        throw 'Synthesis does not match current sources. Run -Stage All.'
    }
    $run=Join-Path $projectRoot 'smart_terminal_Runs/phy_1'
    if ($Stage -eq 'Verify') {
        # Recheck the finished run, e.g. after correcting report publication.
        # Existing output must still match the recorded synthesis snapshot.
        $start=(Get-Item -LiteralPath (Join-Path $run '.opt_gate.begin.f')).LastWriteTimeUtc
        foreach ($step in @('opt_gate','opt_place','opt_route','bitgen')) {
            $end=Get-Item -LiteralPath (Join-Path $run ".$step.end.f")
            $errorFile=Get-Item -LiteralPath (Join-Path $run ".$step.error.f") -ErrorAction SilentlyContinue
            if ($end.LastWriteTimeUtc -lt $start -or ($errorFile -and $errorFile.LastWriteTimeUtc -ge $start)) {
                throw "Finished run did not pass $step in this run. Rebuild before publishing."
            }
        }
    } else {
        $start=Invoke-VerifiedStage 'phy_1' 'phy_settings.cfg' @('opt_gate','opt_place','opt_route','bitgen')
        # The success message emitted by Invoke-VerifiedStage is not a timestamp.
        $start=$start | Where-Object { $_ -is [datetime] } | Select-Object -Last 1
    }
    $bit=Get-Item -LiteralPath (Join-Path $run 'smart_terminal.bit')
    $bin=Get-Item -LiteralPath (Join-Path $run 'smart_terminal.bin')
    if ($bit.LastWriteTimeUtc -lt $start -or $bin.LastWriteTimeUtc -lt $start) { throw 'Bit/bin are stale.' }
    $header=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($bit.FullName),0,1024)
    if ($header -notmatch '# Version: Release_2026\.1_SP2') { throw 'Refusing to publish a bit made by the wrong TD version.' }
    if ((Get-SourceSnapshot) -ne $sourceSnapshot) { throw 'Sources changed during place/route. Refusing to publish.' }
    $timingPath=Join-Path $run 'smart_terminal_phy.ts'
    $timing=Get-Content -LiteralPath $timingPath -Raw
    if ((Get-Item -LiteralPath $timingPath).LastWriteTimeUtc -lt $start -or
        $timing -notmatch 'STNS:\s*0\.000ns' -or $timing -notmatch 'HTNS:\s*0\.000ns' -or
        $timing -match '[SH]WNS:\s*-') { throw 'Fresh passing setup/hold timing is required before publishing.' }
    # TD's DRC checker logs its result but does not create the -file artifact.
    # Retain the actual checker transcript and require all four checks to finish.
    $routeLog=Get-Content -LiteralPath (Join-Path $evidence 'phy_1-build.log') -Raw
    $drc=[regex]::Match($routeLog,'(?s)RUN-1002 : start command "report_route_status -drc[^\r\n]*.*?(?=RUN-1002 : start command "report_area)')
    if (!$drc.Success -or $drc.Value -match 'ERROR|CRITICAL-WARNING' -or
        $drc.Value -notmatch 'End Stage [0-9]+ \| Run Abnormal Path Checker') { throw 'Completed passing route DRC transcript is required.' }
    [IO.File]::WriteAllText((Join-Path $evidence 'smart_terminal_route_drc.rpt'),$drc.Value)
    foreach ($name in @('smart_terminal.bit','smart_terminal.bin')) {
        Copy-Item -LiteralPath (Join-Path $run $name) -Destination (Join-Path $repoRoot "output/$name")
    }
    foreach ($name in @('smart_terminal_phy.ts','smart_terminal_pr.timing','smart_terminal_phy.area','smart_terminal_exception.timing','route.qor')) {
        Copy-Item -LiteralPath (Join-Path $run $name) -Destination (Join-Path $evidence $name)
    }
    $manifest=[ordered]@{
        completedUtc=(Get-Date).ToUniversalTime().ToString('o');tool=$cli;version='Release_2026.1_SP2';
        sources=(ConvertFrom-Json $sourceSnapshot);timing=$timing;
        bitSha256=(Get-FileHash -LiteralPath $bit.FullName -Algorithm SHA256).Hash;
        binSha256=(Get-FileHash -LiteralPath $bin.FullName -Algorithm SHA256).Hash
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidence 'build-manifest.json') -Encoding UTF8
    Write-Output 'Fresh SP2 bit/bin published with matching source hashes and passing setup/hold timing.'
    Get-Content -LiteralPath (Join-Path $run 'smart_terminal_phy.ts')
}
