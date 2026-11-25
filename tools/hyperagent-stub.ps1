$ErrorActionPreference = 'Stop'

$binDir = $PSScriptRoot
$prefix = Split-Path -Parent $binDir
$version = (Get-Content -LiteralPath (Join-Path $prefix 'share\hyperagent\VERSION') -Raw).Trim()
$sourceSha = (Get-Content -LiteralPath (Join-Path $prefix 'share\hyperagent\SOURCE_SHA') -Raw).Trim()
$userDir = Join-Path $env:LOCALAPPDATA 'hyperagent'
$orchHome = if ($env:ORCH_HOME) { $env:ORCH_HOME } else { Join-Path $userDir '.orch' }
$projectParent = if ($env:ORCH_PARENT) { $env:ORCH_PARENT } else { Join-Path $userDir 'projects' }
$templates = if ($env:CCBRIDGE_TEMPLATES) { $env:CCBRIDGE_TEMPLATES } else { Join-Path $prefix 'share\ccbridge\templates' }
$journal = if ($env:ORCH_JOURNAL) { $env:ORCH_JOURNAL } else { Join-Path $orchHome 'projects' }
$root = if ($env:HYPERAGENT_ROOT) { $env:HYPERAGENT_ROOT } else { $prefix }
$manifestPath = Join-Path $orchHome 'install-manifest.json'
$envPath = Join-Path $orchHome 'install-manifest.env'
$mcpTimeout = if ($env:MCP_TIMEOUT) { $env:MCP_TIMEOUT } else { '600000' }
$toolTimeout = if ($env:MCP_TOOL_TIMEOUT) { $env:MCP_TOOL_TIMEOUT } else { '600000' }
$manifestKeys = @('ORCH_HOST', 'ORCH_PARENT', 'ORCH_PORT', 'ORCH_HOME', 'ORCH_JOURNAL', 'HYPERAGENT_ROOT', 'CCBRIDGE_TEMPLATES', 'MCP_TIMEOUT', 'MCP_TOOL_TIMEOUT')
$modelFlag = '--' + 'model'
$modelConflict = $modelFlag + '\s+[^d]'

function Test-PortFree([int]$candidate) {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $candidate)
    try {
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        $listener.Stop()
    }
}

function Get-Port {
    if (Test-PortFree 8787) { return 8787 }
    if ($env:HYPERAGENT_REQUIRE_DEFAULT_PORT -eq '1') { Write-Host 'hyperagent setup: port 8787 occupied and fallback disabled'; exit 1 }
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    return $port
}

function Write-Manifest([int]$port) {
    New-Item -ItemType Directory -Force -Path $orchHome, $projectParent, $journal | Out-Null
    $values = @('127.0.0.1', $projectParent, "$port", $orchHome, $journal, $root, $templates, $mcpTimeout, $toolTimeout)
    $manifest = [ordered]@{}
    for ($i = 0; $i -lt $manifestKeys.Count; $i++) { $manifest[$manifestKeys[$i]] = $values[$i] }
    $manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $lines = @()
    for ($i = 0; $i -lt $manifestKeys.Count; $i++) { $lines += "$($manifestKeys[$i])=$($values[$i])" }
    $lines -join [Environment]::NewLine | Set-Content -LiteralPath $envPath -Encoding UTF8
}

function Register-Mcp {
    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claude) { Write-Host 'setup: claude CLI not found on PATH'; exit 1 }
    & $claude.Source mcp remove hyperagent -s user 2>$null | Out-Null
    $arguments = @('mcp', 'add', '-s', 'user')
    foreach ($line in Get-Content -LiteralPath $envPath) {
        $separator = $line.IndexOf('=')
        if ($separator -lt 1) { continue }
        $key = $line.Substring(0, $separator)
        $value = $line.Substring($separator + 1)
        $arguments += @('-e', "$key=$value")
    }
    $arguments += @('hyperagent', '--', (Join-Path $binDir 'hyperagent.cmd'), 'mcp')
    & $claude.Source @arguments
    if ($LASTEXITCODE -ne 0) { Write-Host "setup: claude mcp add failed with exit code $LASTEXITCODE"; exit 1 }
}

function Run-Setup {
    $port = Get-Port
    Write-Manifest $port
    Register-Mcp
    Write-Host "setup: state directory $orchHome"
    Write-Host "setup: project parent $projectParent"
    Write-Host "setup: port $port"
    Write-Host "setup: templates $templates"
    Write-Host 'setup: MCP registration refreshed'
}

function Run-Doctor {
    if (-not (Test-Path $orchHome)) { Write-Host 'doctor: state directory missing'; exit 1 }
    if (-not (Test-Path $projectParent)) { Write-Host 'doctor: project parent missing'; exit 1 }
    if (-not (Test-Path $manifestPath)) { Write-Host 'doctor: install manifest missing'; exit 1 }
    if (-not (Test-Path $envPath)) { Write-Host 'doctor: install manifest env missing'; exit 1 }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $port = [int]$manifest.ORCH_PORT
    if (-not (Test-PortFree $port)) { Write-Host "doctor: port $port is occupied"; exit 1 }
    foreach ($resource in @('bin\ccbridge.cmd', 'share\ccbridge\templates', 'share\ccbridge\web', 'share\hyperagent\gui\public', '.mcp.json', 'share\hyperagent\scripts', 'share\hyperagent\docs', 'share\hyperagent\tools\mcp-stub.js')) {
        if (-not (Test-Path (Join-Path $prefix $resource))) { Write-Host "doctor: missing $resource"; exit 1 }
    }
    $templateFile = Join-Path $templates 'claude.json'
    if (Test-Path $templateFile) {
        $template = Get-Content -LiteralPath $templateFile -Raw
        if ($template -notlike "*$modelFlag*" -or $template -notlike '*default*') { Write-Host 'doctor: template has no model default'; exit 1 }
        if ($template -match "AIRC_CLAUDE_MODEL|ORCH_CLAUDE_MODEL|ANTHROPIC_MODEL|$modelConflict") { Write-Host 'doctor: conflicting model override'; exit 1 }
    }
    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claude) { Write-Host 'doctor: claude CLI not found on PATH'; exit 1 }
    $mcpGet = (& $claude.Source mcp get hyperagent 2>&1 | Out-String)
    foreach ($line in Get-Content -LiteralPath $envPath) {
        $separator = $line.IndexOf('=')
        if ($separator -lt 1) { continue }
        $key = $line.Substring(0, $separator)
        $value = $line.Substring($separator + 1)
        if ($mcpGet -notlike "*$key=$value*") { Write-Host "doctor: stale MCP registration for $key"; exit 1 }
    }
    Write-Host "doctor: binary $(Join-Path $binDir 'hyperagent.cmd')"
    Write-Host "doctor: version $version"
    Write-Host "doctor: source $sourceSha"
    Write-Host "doctor: ccbridge $(Join-Path $binDir 'ccbridge.cmd')"
    Write-Host "doctor: templates $templates"
    Write-Host "doctor: GUI $(Join-Path $prefix 'share\hyperagent\gui\public')"
    Write-Host "doctor: state $orchHome"
    Write-Host "doctor: parent $projectParent"
    Write-Host "doctor: port $port"
    Write-Host 'doctor: MCP registration current'
    Write-Host 'doctor: no conflicting model override'
    Write-Host 'DOCTOR PASS'
}

function Run-Mcp {
    $env:HYPERAGENT_STUB_VERSION = $version
    & node (Join-Path $prefix 'share\hyperagent\tools\mcp-stub.js')
}

$command = if ($args.Count -gt 0) { $args[0] } else { '' }
switch ($command) {
    '--version' { Write-Host $version }
    'setup' { if ($args.Count -gt 1 -and $args[1] -eq '--check') { Run-Doctor } else { Run-Setup } }
    'doctor' { Run-Doctor }
    'mcp' { Run-Mcp }
    'ccbridge' { Write-Host (Join-Path $binDir 'ccbridge.cmd') }
    default { Write-Host "hyperagent stub: unsupported command $command"; exit 2 }
}
