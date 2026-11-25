$ErrorActionPreference = 'Stop'
param([string]$ReleaseDir, [string]$Version, [string]$Target = '')

if (-not $Target) { $Target = 'x64-windows' }
$archive = "hyperagent-$Target.zip"
if (Test-Path $ReleaseDir) { Remove-Item -LiteralPath $ReleaseDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $ReleaseDir | Out-Null
$staging = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $staging | Out-Null
try {
    $layout = Join-Path $staging "hyperagent-$Target"
    foreach ($directory in @('bin', 'share\ccbridge\templates', 'share\ccbridge\web', 'share\hyperagent\gui\public', 'share\hyperagent\scripts', 'share\hyperagent\docs', 'share\hyperagent\tools')) {
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
    [IO.File]::WriteAllText((Join-Path $layout '.mcp.json'), '{\'mcpServers\':{\'hyperagent\':{\'command\':\'build/hyperagent\',\'args\':[\'mcp\']}}}')
    [IO.File]::WriteAllText((Join-Path $layout 'share\hyperagent\scripts\placeholder'), 'placeholder')
    [IO.File]::WriteAllText((Join-Path $layout 'share\hyperagent\docs\placeholder'), 'placeholder')
    [IO.File]::WriteAllText((Join-Path $layout 'share\ccbridge\templates\claude.json'), '{\'default\': true, \'argv\': [\'chlaude-peer\', \'--model\', \'default\'], \'ready\': [\'Claude Code\'], \'busy\': [\'esc to interrupt\'], \'transcript\': {\'kind\': \'claude-jsonl\', \'root\': \'{home}/.claude/projects\'}}')
    Compress-Archive -Path $layout -DestinationPath (Join-Path $ReleaseDir $archive)
    $hash = (Get-FileHash -Algorithm SHA256 (Join-Path $ReleaseDir $archive)).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $ReleaseDir 'SHA256SUMS'), "$hash  $archive" + [Environment]::NewLine)
    Write-Host $archive
}
finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}
