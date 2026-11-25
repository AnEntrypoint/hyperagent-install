function New-WorkDir {
    if ($env:HYPERAGENT_WITNESS_DIR) {
        $work = $env:HYPERAGENT_WITNESS_DIR
        if (Test-Path $work) { cmd /c rmdir /s /q "$work" 2>$null }
    } else {
        $scratchRoot = if ($env:HYPERAGENT_SCRATCH) { Join-Path $env:HYPERAGENT_SCRATCH 'hyperagent-install' } else { Join-Path $env:LOCALAPPDATA 'hyperagent-install-witness' }
        New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null
        $work = Join-Path $scratchRoot ([IO.Path]::GetRandomFileName())
    }
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    return $work
}

function Get-FreePort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    return $port
}

function Start-FakeServer {
    param([string]$ReleaseDir, [string]$Log, [string]$ToolsDir)
    $port = Get-FreePort
    $serve = Join-Path $ToolsDir 'serve.ps1'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$serve`" -ReleaseDir `"$ReleaseDir`" -Port $port -Log `"$Log`""
    $process = Start-Process -FilePath 'powershell' -ArgumentList $arguments -PassThru -WindowStyle Hidden
    for ($i = 0; $i -lt 40; $i++) {
        if ((Test-Path $Log) -and ((Get-Content -LiteralPath $Log -Raw) -eq 'ready')) { break }
        Start-Sleep -Milliseconds 100
    }
    if (-not ((Test-Path $Log) -and ((Get-Content -LiteralPath $Log -Raw) -eq 'ready'))) { throw 'FAIL: fake release server did not start' }
    return [pscustomobject]@{ Process = $process; Port = $port }
}

function Stop-PidById {
    param([int]$ProcessId)
    if ($ProcessId -gt 0) { Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue }
}

function New-Template {
    param([string]$TemplateDir)
    New-Item -ItemType Directory -Force -Path $TemplateDir | Out-Null
    $json = '{"default": true, "argv": ["chlaude-peer"], "ready": ["Claude Code"], "busy": ["esc to interrupt"], "transcript": {"kind": "claude-jsonl", "root": "{home}/.claude/projects"}}'
    [IO.File]::WriteAllText((Join-Path $TemplateDir 'claude.json'), $json)
}

function Get-ManifestValue {
    param([string]$ManifestPath, [string]$Name)
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    return $manifest.$Name
}

function Assert-McpEnv {
    param([string]$EnvPath)
    $mcpGet = (& claude mcp get hyperagent 2>&1 | Out-String)
    foreach ($line in Get-Content -LiteralPath $EnvPath) {
        $separator = $line.IndexOf('=')
        if ($separator -lt 1) { continue }
        $key = $line.Substring(0, $separator)
        $value = $line.Substring($separator + 1)
        if ($mcpGet -notlike "*$key=$value*") { throw "FAIL: MCP config missing $key" }
    }
}

function Assert-Connected {
    $mcpList = (& claude mcp list 2>&1 | Out-String)
    if ($mcpList -notlike '*Connected*') { throw "FAIL: MCP registration not connected`n$mcpList" }
}
function Set-TestPath {
    param([string]$ToolsDir)
    if ($env:HYPERAGENT_REAL_CLAUDE -ne '1') {
        $env:PATH = (Join-Path $ToolsDir 'claude-bin') + ';' + $env:PATH
    }
}

function Test-PortFree {
    param([int]$Port)
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    try {
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        $listener.Stop()
    }
}

function Start-PortHolder {
    param([int]$Port = 8787, [string]$Log, [string]$ToolsDir)
    if (-not (Test-PortFree $Port)) { return $null }
    $holder = Join-Path $ToolsDir 'hold-port.ps1'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$holder`" -Port $Port -Log `"$Log`""
    $process = Start-Process -FilePath 'powershell' -ArgumentList $arguments -PassThru -WindowStyle Hidden
    for ($i = 0; $i -lt 40; $i++) {
        if ((Test-Path $Log) -and ((Get-Content -LiteralPath $Log -Raw) -eq 'ready')) { break }
        Start-Sleep -Milliseconds 100
    }
    if (-not ((Test-Path $Log) -and ((Get-Content -LiteralPath $Log -Raw) -eq 'ready'))) { throw 'FAIL: port holder did not start' }
    return $process
}
function Clear-SetupEnv {
    foreach ($name in @('ORCH_HOME', 'ORCH_PARENT', 'ORCH_PORT', 'ORCH_JOURNAL', 'HYPERAGENT_ROOT', 'CCBRIDGE_TEMPLATES', 'MCP_TIMEOUT', 'MCP_TOOL_TIMEOUT', 'HYPERAGENT_REQUIRE_DEFAULT_PORT', 'ORCH_CLAUDE_MODEL', 'AIRC_CLAUDE_MODEL')) {
        Remove-Item Env:$name -ErrorAction SilentlyContinue
    }
}

function New-PartialRelease {
    param([string]$ReleaseDir)
    $manifestPath = Join-Path $ReleaseDir 'manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.targets.PSObject.Properties.Remove('x64-macos')
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 5))
    $lines = @()
    foreach ($line in Get-Content -LiteralPath (Join-Path $ReleaseDir 'SHA256SUMS')) {
        $parts = $line -split '\s+'
        if ($parts.Count -ge 2 -and $parts[1] -notlike '*x64-macos*') { $lines += $line }
    }
    [IO.File]::WriteAllText((Join-Path $ReleaseDir 'SHA256SUMS'), ($lines -join [Environment]::NewLine) + [Environment]::NewLine)
}

function New-MissingChecksumRelease {
    param([string]$ReleaseDir)
    $lines = @()
    foreach ($line in Get-Content -LiteralPath (Join-Path $ReleaseDir 'SHA256SUMS')) {
        $parts = $line -split '\s+'
        if ($parts.Count -ge 2 -and $parts[1] -ne 'hyperagent-x64-macos.tar.gz') { $lines += $line }
    }
    [IO.File]::WriteAllText((Join-Path $ReleaseDir 'SHA256SUMS'), ($lines -join [Environment]::NewLine) + [Environment]::NewLine)
}
