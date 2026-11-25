param([string]$ReleaseDir, [string]$Version, [string]$Target = '')
$ErrorActionPreference = 'Stop'

if (-not $Target) { $Target = 'x64-windows' }
$archive = "hyperagent-$Target.zip"
if (Test-Path $ReleaseDir) { Remove-Item -LiteralPath $ReleaseDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $ReleaseDir | Out-Null
$scratchRoot = if ($env:HYPERAGENT_SCRATCH) { Join-Path $env:HYPERAGENT_SCRATCH 'hyperagent-install' } else { Join-Path $ReleaseDir 'scratch' }
New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null
$staging = Join-Path $scratchRoot ([IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $staging | Out-Null
try {
    $layout = Join-Path $staging "hyperagent-$Target"
    foreach ($directory in @('bin', 'share\ccbridge\templates', 'share\ccbridge\web', 'share\hyperagent\gui\public', 'share\hyperagent\tools', 'scripts', 'docs', 'tools')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $layout $directory) | Out-Null
    }
    $toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    Copy-Item -LiteralPath (Join-Path $toolsDir 'hyperagent-stub.ps1') -Destination (Join-Path $layout 'bin\hyperagent-stub.ps1')
    Copy-Item -LiteralPath (Join-Path $toolsDir 'hyperagent.cmd') -Destination (Join-Path $layout 'bin\hyperagent.cmd')
    Copy-Item -LiteralPath (Join-Path $toolsDir 'ccbridge.cmd') -Destination (Join-Path $layout 'bin\ccbridge.cmd')
    Copy-Item -LiteralPath (Join-Path $toolsDir 'mcp-stub.js') -Destination (Join-Path $layout 'share\hyperagent\tools\mcp-stub.js')
    [IO.File]::WriteAllText((Join-Path $layout 'share\hyperagent\VERSION'), $Version + [Environment]::NewLine)
    $sourceSha = if ($env:HYPERAGENT_SOURCE_SHA) { $env:HYPERAGENT_SOURCE_SHA } else { 'witness-sha' }
    [IO.File]::WriteAllText((Join-Path $layout 'share\hyperagent\SOURCE_SHA'), $sourceSha + [Environment]::NewLine)
    [IO.File]::WriteAllText((Join-Path $layout 'share\ccbridge\web\index.html'), '<html></html>')
    [IO.File]::WriteAllText((Join-Path $layout 'share\hyperagent\gui\public\index.html'), '<html></html>')
    [IO.File]::WriteAllText((Join-Path $layout '.mcp.json'), '{"mcpServers":{"hyperagent":{"command":"build/hyperagent","args":["mcp"]}}}')
    [IO.File]::WriteAllText((Join-Path $layout 'scripts\placeholder'), 'placeholder')
    [IO.File]::WriteAllText((Join-Path $layout 'docs\placeholder'), 'placeholder')
    [IO.File]::WriteAllText((Join-Path $layout 'tools\placeholder'), 'placeholder')
    [IO.File]::WriteAllText((Join-Path $layout 'share\ccbridge\templates\claude.json'), '{"default": true, "argv": ["chlaude-peer"], "ready": ["Claude Code"], "busy": ["esc to interrupt"], "transcript": {"kind": "claude-jsonl", "root": "{home}/.claude/projects"}}')
    Compress-Archive -Path $layout -DestinationPath (Join-Path $ReleaseDir $archive)
    $hash = (Get-FileHash -Algorithm SHA256 (Join-Path $ReleaseDir $archive)).Hash.ToLowerInvariant()
    $targets = @('arm64-linux', 'arm64-macos', 'x64-linux', 'x64-macos', 'x64-windows')
    $build = "$Version-23"
    $manifestTargets = [ordered]@{}
    foreach ($name in $targets) {
        $ext = if ($name -eq 'x64-windows') { 'zip' } else { 'tar.gz' }
        $manifestTargets[$name] = [ordered]@{ asset = "hyperagent-$build-$name.$ext"; sha256 = ('0' * 64); size = 1 }
    }
    $manifest = [ordered]@{ build = $build; sha = $sourceSha; targets = $manifestTargets }
    [IO.File]::WriteAllText((Join-Path $ReleaseDir 'manifest.json'), ($manifest | ConvertTo-Json -Depth 5))
    $lines = @()
    foreach ($name in $targets) {
        $ext = if ($name -eq 'x64-windows') { 'zip' } else { 'tar.gz' }
        $stable = "hyperagent-$name.$ext"
        $checksum = if ($stable -eq $archive) { $hash } else { '0' * 64 }
        $lines += "$checksum  $stable"
    }
    foreach ($name in $targets) {
        $ext = if ($name -eq 'x64-windows') { 'zip' } else { 'tar.gz' }
        $lines += ('0' * 64) + "  hyperagent-$build-$name.$ext"
    }
    [IO.File]::WriteAllText((Join-Path $ReleaseDir 'SHA256SUMS'), ($lines -join [Environment]::NewLine) + [Environment]::NewLine)
    Write-Host $archive
}
finally {
    cmd /c rmdir /s /q "$staging" 2>$null
}
