$ErrorActionPreference = 'Stop'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = Split-Path -Parent $toolsDir
. (Join-Path $toolsDir 'common.ps1')
Set-TestPath $toolsDir
Clear-SetupEnv
$work = New-WorkDir
$server = $null
$holder = $null
try {
    $homeDir = Join-Path $work 'home'
    $localAppData = Join-Path $homeDir 'AppData\Local'
    $appData = Join-Path $homeDir 'AppData\Roaming'
    $tempDir = Join-Path $work 'temp'
    $releaseDir = Join-Path $work 'fake-latest'
    $templateDir = Join-Path $work 'templates'
    $installScript = Join-Path $repoDir 'install.ps1'
    $fakeRelease = Join-Path $toolsDir 'fake-release.ps1'
    $installRoot = Join-Path $localAppData 'hyperagent'
    $binDir = Join-Path $installRoot 'current\bin'
    $orchHome = Join-Path $installRoot '.orch'
    $manifestPath = Join-Path $orchHome 'install-manifest.json'
    $envPath = Join-Path $orchHome 'install-manifest.env'
    $sourceSha = if ($env:HYPERAGENT_SOURCE_SHA) { $env:HYPERAGENT_SOURCE_SHA } else { 'witness-sha' }
    $env:HYPERAGENT_SOURCE_SHA = $sourceSha
    $env:HYPERAGENT_EXPECTED_SOURCE_SHA = $sourceSha
    New-Template $templateDir
    function Reset-Home {
        Clear-SetupEnv
        if (Test-Path $homeDir) { cmd /c rmdir /s /q "$homeDir" 2>$null }
        foreach ($directory in @($homeDir, $localAppData, $appData, $tempDir)) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
        $env:USERPROFILE = $homeDir
        $env:HOME = $homeDir
        $env:LOCALAPPDATA = $localAppData
        $env:APPDATA = $appData
        $env:TEMP = $tempDir
        $env:TMP = $tempDir
        $env:PATH = "$binDir;$env:PATH"
        Set-TestPath $ToolsDir
    }
    function New-Release {
        param([string]$Version, [string]$Target = 'x64-windows')
        & powershell -NoProfile -ExecutionPolicy Bypass -File $fakeRelease -ReleaseDir $releaseDir -Version $Version -Target $Target | Out-Null
    }
    function Invoke-DoctorLog {
        param([string]$Log)
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & hyperagent doctor *> $Log
        $code = $LASTEXITCODE
        $ErrorActionPreference = $previousPreference
        return $code
    }
    function Invoke-Install {
        param([string]$Log, [string]$Expected = '1.0.0')
        $env:HYPERAGENT_EXPECTED_VERSION = $Expected
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & powershell -NoProfile -ExecutionPolicy Bypass -File $installScript *> $Log
        $code = $LASTEXITCODE
        $ErrorActionPreference = $previousPreference
        return $code
    }
    function Assert-Failure {
        param([string]$Name, [string]$Log, [string]$Pattern, [scriptblock]$Command)
        $code = & $Command
        if ($code -eq 0) { throw "RED FAIL: $Name was accepted" }
        $text = Get-Content -LiteralPath $Log -Raw
        if ($text -notlike "*$Pattern*") { Write-Host $text; throw "RED FAIL: $Name lacked $Pattern" }
        Write-Host "RED PASS: $Name"
    }
    Reset-Home
    New-Release '1.0.0'
    $server = Start-FakeServer -ReleaseDir $releaseDir -Log (Join-Path $work 'server.log') -ToolsDir $toolsDir
    $env:HYPERAGENT_RELEASE_BASE = "http://127.0.0.1:$($server.Port)"
    $env:HYPERAGENT_TEMPLATES = $templateDir
    $archive = ((Get-Content -LiteralPath (Join-Path $releaseDir 'SHA256SUMS') -Raw) -split '\s+')[1]
    $archivePath = Join-Path $releaseDir $archive
    $bytes = [IO.File]::ReadAllBytes($archivePath)
    $bytes[10] = 88
    [IO.File]::WriteAllBytes($archivePath, $bytes)
    Assert-Failure 'corrupted archive refused' (Join-Path $work 'bad-checksum.log') 'sha256 mismatch' { Invoke-Install (Join-Path $work 'bad-checksum.log') }
    if (Test-Path $installRoot) { throw 'RED FAIL: something was installed' }
    Reset-Home
    New-Release '1.0.0' 'arm64-windows'
    Assert-Failure 'wrong artifact refused' (Join-Path $work 'wrong-target.log') 'SHA256SUMS has no entry' { Invoke-Install (Join-Path $work 'wrong-target.log') }
    Reset-Home
    New-Release '1.0.0'
    $holder = Start-PortHolder -Port 8787 -Log (Join-Path $work 'holder.log') -ToolsDir $toolsDir
    $env:HYPERAGENT_REQUIRE_DEFAULT_PORT = '1'
    Assert-Failure 'occupied default port fails without fallback' (Join-Path $work 'occupied-port.log') 'port 8787 occupied and fallback disabled' { Invoke-Install (Join-Path $work 'occupied-port.log') }
    Remove-Item Env:HYPERAGENT_REQUIRE_DEFAULT_PORT -ErrorAction SilentlyContinue
    if ($holder) { Stop-PidById $holder.Id; $holder = $null }
    Reset-Home
    New-Release '1.0.0'
    $code = Invoke-Install (Join-Path $work 'valid.log')
    if ($code -ne 0) { throw 'RED FAIL: valid install failed' }
    $parent = Get-ManifestValue -ManifestPath $manifestPath -Name 'ORCH_PARENT'
    Remove-Item -LiteralPath $parent -Recurse -Force -ErrorAction SilentlyContinue
    $doctorLog = Join-Path $work 'missing-parent.log'
    $code = Invoke-DoctorLog $doctorLog
    if ($code -eq 0) { throw 'RED FAIL: missing project parent was accepted' }
    $doctorText = Get-Content -LiteralPath $doctorLog -Raw
    Write-Host $doctorText
    if ($doctorText -notlike '*project parent missing*') { throw 'RED FAIL: no missing parent message' }
    Write-Host 'RED PASS: missing project parent fails doctor'
    Reset-Home
    New-Release '1.0.0'
    $code = Invoke-Install (Join-Path $work 'valid-resource.log')
    if ($code -ne 0) { throw 'RED FAIL: valid install failed' }
    Remove-Item -LiteralPath (Join-Path $installRoot 'current\.mcp.json') -Force
    $doctorLog = Join-Path $work 'missing-resource.log'
    $code = Invoke-DoctorLog $doctorLog
    if ($code -eq 0) { throw 'RED FAIL: missing resource was accepted' }
    $doctorText = Get-Content -LiteralPath $doctorLog -Raw
    Write-Host $doctorText
    if ($doctorText -notlike '*missing .mcp.json*') { throw 'RED FAIL: no missing resource message' }
    Write-Host 'RED PASS: missing shipped resource fails doctor'
    Reset-Home
    New-Release '1.0.0'
    $code = Invoke-Install (Join-Path $work 'valid-mcp.log')
    if ($code -ne 0) { throw 'RED FAIL: valid install failed' }
    & claude mcp remove hyperagent -s user | Out-Null
    & claude mcp add -s user hyperagent -- (Join-Path $binDir 'hyperagent.cmd') mcp | Out-Null
    $doctorLog = Join-Path $work 'stale-mcp.log'
    $code = Invoke-DoctorLog $doctorLog
    if ($code -eq 0) { throw 'RED FAIL: stale MCP registration was accepted' }
    $doctorText = Get-Content -LiteralPath $doctorLog -Raw
    Write-Host $doctorText
    if ($doctorText -notlike '*stale MCP registration*') { throw 'RED FAIL: no stale MCP message' }
    Write-Host 'RED PASS: stale MCP registration fails doctor'
    Reset-Home
    New-Release '1.0.0'
    $code = Invoke-Install (Join-Path $work 'valid-collision.log')
    if ($code -ne 0) { throw 'RED FAIL: valid install failed' }
    $port = Get-ManifestValue -ManifestPath $manifestPath -Name 'ORCH_PORT'
    $holder = Start-PortHolder -Port ([int]$port) -Log (Join-Path $work 'collision-holder.log') -ToolsDir $toolsDir
    $doctorLog = Join-Path $work 'port-collision.log'
    $code = Invoke-DoctorLog $doctorLog
    if ($code -eq 0) { throw 'RED FAIL: port collision was accepted' }
    $doctorText = Get-Content -LiteralPath $doctorLog -Raw
    Write-Host $doctorText
    if ($doctorText -notlike "*port $port is occupied*") { throw 'RED FAIL: no port collision message' }
    if ($holder) { Stop-PidById $holder.Id; $holder = $null }
    Write-Host 'RED PASS: port collision fails doctor'
    Reset-Home
    New-Release '1.0.0'
    Assert-Failure 'wrong installed version refused' (Join-Path $work 'wrong-version.log') 'does not match expected' { Invoke-Install (Join-Path $work 'wrong-version.log') 'wrong' }
    Reset-Home
    New-Release '1.0.0'
    New-PartialRelease $releaseDir
    Assert-Failure 'four-target manifest refused' (Join-Path $work 'partial-manifest.log') 'partial release' { Invoke-Install (Join-Path $work 'partial-manifest.log') }
    if (Test-Path $installRoot) { throw 'RED FAIL: partial manifest installed' }
    Reset-Home
    New-Release '1.0.0'
    New-MissingChecksumRelease $releaseDir
    Assert-Failure 'missing x64-macos checksum refused' (Join-Path $work 'missing-checksum.log') 'missing checksum' { Invoke-Install (Join-Path $work 'missing-checksum.log') }
    $syntaxLog = Join-Path $work 'syntax.log'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $toolsDir 'syntax.ps1') *> $syntaxLog
    if ($LASTEXITCODE -ne 0) { throw 'RED FAIL: syntax witness failed' }
    $syntaxText = Get-Content -LiteralPath $syntaxLog -Raw
    if ($syntaxText -notlike '*POWERSHELL SYNTAX PASS*') { throw 'RED FAIL: no syntax pass' }
    Write-Host 'RED PASS: hardcoded path, model override and token checks'
    Write-Host 'RED PASS: bad checksum, wrong artifact, occupied port, missing parent, missing resource, stale MCP, port collision, wrong version, four-target manifest, missing x64-macos checksum and portability'
}
finally {
    if ($server) { Stop-PidById $server.Process.Id }
    if ($holder) { Stop-PidById $holder.Id }
    cmd /c rmdir /s /q "$work" 2>$null
}
