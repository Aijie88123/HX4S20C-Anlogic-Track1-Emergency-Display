param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
if(!$OutputDirectory){$OutputDirectory=Join-Path $projectRoot 'evidence/emergency_console_20261027/console'}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $projectRoot 'tools/emergency_console_core.cs'))+"`n"+[IO.File]::ReadAllText((Join-Path $projectRoot 'tests/console_fake_transport.cs'))) -ReferencedAssemblies System.Drawing
[ConsoleTests.Checks]::Run($OutputDirectory,(Join-Path $projectRoot 'evidence/uart_service_20261026/link/wire.txt'))
