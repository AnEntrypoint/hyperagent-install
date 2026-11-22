$ErrorActionPreference = 'Stop'

$releaseBase = if ($env:HYPERAGENT_RELEASE_BASE) { $env:HYPERAGENT_RELEASE_BASE } else { 'https://github.com/AnEntrypoint/hyperagent/releases/download/latest' }

function Fail($message) {
    Write-Error "hyperagent install: $message"
    exit 1
}

if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -notin @('AMD64')) {
    Fail "unsupported architecture $env:PROCESSOR_ARCHITECTURE; only Windows x64 is published"
}

$target = 'x64-windows'
$archive = "hyperagent-$target.zip"
$installRoot = Join-Path $env:LOCALAPPDATA 'hyperagent'
$versionsDir = Join-Path $installRoot 'versions'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $scratch | Out-Null

try {
    Write-Host "downloading $archive from $releaseBase"
    Invoke-WebRequest -UseBasicParsing -Uri "$releaseBase/SHA256SUMS" -OutFile (Join-Path $scratch 'SHA256SUMS')
    Invoke-WebRequest -UseBasicParsing -Uri "$releaseBase/$archive" -OutFile (Join-Path $scratch $archive)

    $entry = Get-Content (Join-Path $scratch 'SHA256SUMS') | Where-Object { ($_ -split '\s+')[1] -eq $archive } | Select-Object -First 1
    if (-not $entry) { Fail "SHA256SUMS has no entry for $archive" }
    $expected = ($entry -split '\s+')[0]
    $actual = (Get-FileHash -Algorithm SHA256 (Join-Path $scratch $archive)).Hash
    if ($expected -ne $actual) { Fail "sha256 mismatch for $archive: expected $expected, got $actual; nothing was installed" }

    $unpacked = Join-Path $scratch 'unpacked'
    Expand-Archive -Path (Join-Path $scratch $archive) -DestinationPath $unpacked
    $source = Join-Path $unpacked "hyperagent-$target"
    if (-not (Test-Path (Join-Path $source 'bin\hyperagent.exe'))) { Fail 'the archive has no bin\hyperagent.exe' }

    $versionName = (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')
    New-Item -ItemType Directory -Force -Path $versionsDir | Out-Null
    $versionDir = Join-Path $versionsDir $versionName
    Move-Item $source $versionDir

    $currentLink = Join-Path $installRoot 'current'
    $previous = $null
    if (Test-Path $currentLink) {
        $previous = (Get-Item $currentLink).Target
        Remove-Item $currentLink -Force
    }
    New-Item -ItemType Junction -Path $currentLink -Target $versionDir | Out-Null

    Get-ChildItem $versionsDir -Directory | Where-Object { $_.FullName -ne $versionDir -and $_.FullName -ne $previous } | Remove-Item -Recurse -Force

    $binDir = Join-Path $currentLink 'bin'
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($userPath -split ';') -notcontains $binDir) {
        [Environment]::SetEnvironmentVariable('Path', "$userPath;$binDir", 'User')
        $pathChanged = $true
    }

    $exe = Join-Path $binDir 'hyperagent.exe'
    Write-Host "installed $versionName"
    & $exe --version
    & $exe setup
}
finally {
    Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'What is left to do:'
if ($pathChanged) { Write-Host '  - Open a new terminal so the updated PATH applies.' }
Write-Host '  - Install the claude CLI if you have not: https://docs.claude.com/en/docs/claude-code'
Write-Host '  - Run: hyperagent --help'
