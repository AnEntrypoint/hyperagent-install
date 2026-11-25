$ErrorActionPreference = 'Stop'

function Fail($message) {
    throw "hyperagent install: $message"
}

$releaseBase = if ($env:HYPERAGENT_RELEASE_BASE) { $env:HYPERAGENT_RELEASE_BASE } else { 'https://github.com/AnEntrypoint/hyperagent/releases/download/latest' }
$expectedVersion = if ($env:HYPERAGENT_EXPECTED_VERSION) { $env:HYPERAGENT_EXPECTED_VERSION } else { '' }
$templatesDir = if ($env:HYPERAGENT_TEMPLATES) { $env:HYPERAGENT_TEMPLATES } else { '' }

if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    Fail "unsupported architecture $env:PROCESSOR_ARCHITECTURE; only Windows x64 is published"
}

$target = 'x64-windows'
$archive = "hyperagent-$target.zip"
$installRoot = Join-Path $env:LOCALAPPDATA 'hyperagent'
$versionsDir = Join-Path $installRoot 'versions'
$currentLink = Join-Path $installRoot 'current'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $scratch | Out-Null
$versionDir = ''
$previous = $null
$committed = $false
$pathChanged = $false

try {
    Write-Host "downloading $archive from $releaseBase"
    Invoke-WebRequest -UseBasicParsing -Uri "$releaseBase/SHA256SUMS" -OutFile (Join-Path $scratch 'SHA256SUMS')
    $entry = Get-Content (Join-Path $scratch 'SHA256SUMS') | Where-Object { ($_ -split '\s+')[1] -eq $archive } | Select-Object -First 1
    if (-not $entry) { Fail "SHA256SUMS has no entry for $archive" }
    $expected = ($entry -split '\s+')[0]
    Invoke-WebRequest -UseBasicParsing -Uri "$releaseBase/$archive" -OutFile (Join-Path $scratch $archive)
    $actual = (Get-FileHash -Algorithm SHA256 (Join-Path $scratch $archive)).Hash.ToLowerInvariant()
    if ($expected.ToLowerInvariant() -ne $actual) { Fail "sha256 mismatch for ${archive}: expected $expected, got $actual; nothing was installed" }

    $unpacked = Join-Path $scratch 'unpacked'
    Expand-Archive -Path (Join-Path $scratch $archive) -DestinationPath $unpacked
    $source = Join-Path $unpacked "hyperagent-$target"
    $exeName = 'hyperagent.exe'
    $exeSource = Join-Path $source (Join-Path 'bin' $exeName)
    if (-not (Test-Path $exeSource)) {
        $exeName = 'hyperagent.cmd'
        $exeSource = Join-Path $source (Join-Path 'bin' $exeName)
    }
    if (-not (Test-Path $exeSource)) { Fail 'the archive has no bin\hyperagent.exe or bin\hyperagent.cmd' }
    $ccbridgeCandidates = @('bin\ccbridge.exe', 'bin\ccbridge.cmd')
    if (-not ($ccbridgeCandidates | Where-Object { Test-Path (Join-Path $source $_) })) { Fail 'the archive has no bin\ccbridge.exe or bin\ccbridge.cmd' }
    foreach ($resource in @('share\ccbridge\templates', 'share\ccbridge\web', 'share\hyperagent\gui\public', '.mcp.json', 'share\hyperagent\scripts', 'share\hyperagent\docs')) {
        if (-not (Test-Path (Join-Path $source $resource))) { Fail "the archive has no $resource" }
    }

    $versionName = (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $versionDir = Join-Path $versionsDir $versionName
    New-Item -ItemType Directory -Force -Path $versionsDir | Out-Null
    Move-Item -LiteralPath $source -Destination $versionDir

    if (Test-Path $currentLink) {
        $previous = (Get-Item -LiteralPath $currentLink).Target
        Remove-Item -LiteralPath $currentLink -Force -Recurse
    }
    $newLink = Join-Path $installRoot 'current.new'
    if (Test-Path $newLink) { Remove-Item -LiteralPath $newLink -Force -Recurse }
    New-Item -ItemType Junction -Path $newLink -Target $versionDir | Out-Null
    Rename-Item -LiteralPath $newLink -NewName 'current'

    $binDir = Join-Path $currentLink 'bin'
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { $userPath = '' }
    if (($userPath -split ';') -notcontains $binDir) {
        [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $binDir), 'User')
        $pathChanged = $true
    }

    $exe = Join-Path $binDir $exeName
    $versionOutput = (& $exe --version | Out-String).Trim()
    if ($expectedVersion -and $versionOutput -ne $expectedVersion) { Fail "installed version $versionOutput does not match expected $expectedVersion" }
    Write-Host "installed $versionName"
    Write-Host $versionOutput

    if ($templatesDir) { $env:CCBRIDGE_TEMPLATES = $templatesDir }
    $setupOutput = & $exe setup 2>&1 | Out-String
    $setupCode = $LASTEXITCODE
    Write-Host $setupOutput.TrimEnd()
    if ($setupCode -ne 0) { Fail "setup failed with exit code $setupCode" }

    $doctorOutput = & $exe doctor 2>&1 | Out-String
    $doctorCode = $LASTEXITCODE
    if ($doctorCode -ne 0) {
        $checkOutput = & $exe setup --check 2>&1 | Out-String
        $checkCode = $LASTEXITCODE
        if ($checkCode -ne 0) {
            Write-Error $doctorOutput.TrimEnd()
            Write-Error $checkOutput.TrimEnd()
            Fail 'doctor report failed'
        }
        Write-Host $checkOutput.TrimEnd()
    } else {
        Write-Host $doctorOutput.TrimEnd()
    }

    Get-ChildItem -LiteralPath $versionsDir -Directory | Where-Object { $_.FullName -ne $versionDir -and $_.FullName -ne $previous } | Remove-Item -Recurse -Force
    $committed = $true

    Write-Host ''
    Write-Host 'Restart Claude Code so the hyperagent MCP registration reloads.'
    if ($pathChanged) { Write-Host 'Open a new terminal so the updated PATH applies.' }
    Write-Host 'Set CCBRIDGE_TEMPLATES before setup for a chlaude-compatible harness and keep --model default.'
}
finally {
    if (-not $committed) {
        $newLink = Join-Path $installRoot 'current.new'
        if (Test-Path $newLink) { Remove-Item -LiteralPath $newLink -Force -Recurse -ErrorAction SilentlyContinue }
        if (Test-Path $currentLink) { Remove-Item -LiteralPath $currentLink -Force -Recurse -ErrorAction SilentlyContinue }
        if ($previous) { New-Item -ItemType Junction -Path $currentLink -Target $previous -ErrorAction SilentlyContinue | Out-Null }
        if ($versionDir -and (Test-Path $versionDir)) { Remove-Item -LiteralPath $versionDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
