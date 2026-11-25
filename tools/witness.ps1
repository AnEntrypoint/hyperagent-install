$ErrorActionPreference = 'Stop'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = Split-Path -Parent $toolsDir
. (Join-Path $toolsDir 'common.ps1')
Set-TestPath $toolsDir
$work = New-WorkDir
$server = $null
$holder = $null
try {
    $homeDir = Join-Path $work 'home'
    $localAppData = Join-Path $homeDir 'AppData\Local'
    $appData = Join-Path $homeDir 'AppData\Roaming'
    $tempDir = Join-Path $work 'temp'
    foreach ($directory in @($homeDir, $localAppData, $appData, $tempDir)) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
    $env:USERPROFILE = $homeDir
    $env:HOME = $homeDir
    $env:LOCALAPPDATA = $localAppData
    $env:APPDATA = $appData
    $env:TEMP = $tempDir
    $env:TMP = $tempDir
    $releaseDir = Join-Path $work 'fake-latest'
    $templateDir = Join-Path $work 'templates'
    New-Template $templateDir
    $expectedVersion = if ($env:HYPERAGENT_EXPECTED_VERSION) { $env:HYPERAGENT_EXPECTED_VERSION } else { '1.0.0' }
    $sourceSha = if ($env:HYPERAGENT_SOURCE_SHA) { $env:HYPERAGENT_SOURCE_SHA } else { 'witness-sha' }
    $env:HYPERAGENT_SOURCE_SHA = $sourceSha
    $fakeRelease = Join-Path $toolsDir 'fake-release.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $fakeRelease -ReleaseDir $releaseDir -Version $expectedVersion | Out-Null
    $server = Start-FakeServer -ReleaseDir $releaseDir -Log (Join-Path $work 'server.log') -ToolsDir $toolsDir
    $env:HYPERAGENT_RELEASE_BASE = "http://127.0.0.1:$($server.Port)"
    $env:HYPERAGENT_EXPECTED_VERSION = $expectedVersion
    $env:HYPERAGENT_TEMPLATES = $templateDir
    $holder = Start-PortHolder -Port 8787 -Log (Join-Path $work 'holder.log') -ToolsDir $toolsDir
    $installScript = Join-Path $repoDir 'install.ps1'
    $install1 = Join-Path $work 'install1.log'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installScript *> $install1
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: install.ps1 failed' }
    $install1Text = Get-Content -LiteralPath $install1 -Raw
    if ($install1Text -notlike '*DOCTOR PASS*') { throw 'FAIL: doctor report missing' }
    if ($install1Text -notlike '*Restart Claude Code*') { throw 'FAIL: restart note missing' }
    $installRoot = Join-Path $localAppData 'hyperagent'
    $binDir = Join-Path $installRoot 'current\bin'
    $env:PATH = "$binDir;$env:PATH"
    $versionOutput = (& hyperagent --version | Out-String).Trim()
    if ($versionOutput -ne $expectedVersion) { throw "FAIL: version after install $versionOutput" }
    if (-not (Test-Path (Join-Path $binDir 'hyperagent.cmd'))) { throw 'FAIL: installed launcher missing' }
    $orchHome = Join-Path $installRoot '.orch'
    $manifestPath = Join-Path $orchHome 'install-manifest.json'
    $envPath = Join-Path $orchHome 'install-manifest.env'
    $port = Get-ManifestValue -ManifestPath $manifestPath -Name 'ORCH_PORT'
    if ([int]$port -eq 8787) { throw 'FAIL: no port fallback' }
    $parent = Get-ManifestValue -ManifestPath $manifestPath -Name 'ORCH_PARENT'
    if (-not (Test-Path $parent)) { throw 'FAIL: project parent missing' }
    $envText = Get-Content -LiteralPath $envPath -Raw
    if ($envText -notlike "*$templateDir*") { throw 'FAIL: custom template not persisted' }
    Assert-McpEnv -EnvPath $envPath
    Assert-Connected
    if ($holder) { Stop-PidById $holder.Id; $holder = $null }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $fakeRelease -ReleaseDir $releaseDir -Version '2.0.0' | Out-Null
    $env:HYPERAGENT_EXPECTED_VERSION = '2.0.0'
    $install2 = Join-Path $work 'install2.log'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installScript *> $install2
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: second install failed' }
    $versionOutput = (& hyperagent --version | Out-String).Trim()
    if ($versionOutput -ne '2.0.0') { throw 'FAIL: version after update' }
    $versionCount = (Get-ChildItem -LiteralPath (Join-Path $installRoot 'versions') -Directory).Count
    if ($versionCount -ne 2) { throw 'FAIL: previous version not kept' }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $fakeRelease -ReleaseDir $releaseDir -Version '3.0.0' | Out-Null
    $env:HYPERAGENT_EXPECTED_VERSION = '3.0.0'
    $install3 = Join-Path $work 'install3.log'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installScript *> $install3
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: third install failed' }
    $versionOutput = (& hyperagent --version | Out-String).Trim()
    if ($versionOutput -ne '3.0.0') { throw 'FAIL: version after prune' }
    $versionCount = (Get-ChildItem -LiteralPath (Join-Path $installRoot 'versions') -Directory).Count
    if ($versionCount -ne 2) { throw 'FAIL: older versions not pruned' }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $fakeRelease -ReleaseDir $releaseDir -Version $expectedVersion | Out-Null
    $env:HYPERAGENT_EXPECTED_VERSION = $expectedVersion
    Remove-Item -LiteralPath $homeDir -Recurse -Force
    foreach ($directory in @($homeDir, $localAppData, $appData, $tempDir)) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
    $installClean = Join-Path $work 'install-clean.log'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installScript *> $installClean
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: clean reinstall failed' }
    $versionOutput = (& hyperagent --version | Out-String).Trim()
    if ($versionOutput -ne $expectedVersion) { throw 'FAIL: version after clean reinstall' }
    $doctorClean = Join-Path $work 'doctor-clean.log'
    & hyperagent doctor *> $doctorClean
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: clean doctor failed' }
    $doctorText = Get-Content -LiteralPath $doctorClean -Raw
    if ($doctorText -notlike '*DOCTOR PASS*') { throw 'FAIL: clean doctor report missing' }
    Assert-McpEnv -EnvPath $envPath
    Assert-Connected
    foreach ($log in (Get-ChildItem -LiteralPath $work -Filter 'install*.log')) {
        $text = Get-Content -LiteralPath $log.FullName -Raw
        if ($text -match 'warning|failed|error') { throw "FAIL: unexpected warning, failure or error in $($log.Name)" }
    }
    Write-Host "WITNESS PASS: $expectedVersion $sourceSha install, doctor, port fallback, MCP env, connected, update, pruning, clean reinstall"
}
finally {
    if ($server) { Stop-PidById $server.Process.Id }
    if ($holder) { Stop-PidById $holder.Id }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
