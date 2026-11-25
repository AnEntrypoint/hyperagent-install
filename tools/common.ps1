function New-WorkDir {
    if ($env:HYPERAGENT_WITNESS_DIR) {
        $work = $env:HYPERAGENT_WITNESS_DIR
        if (Test-Path $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    } else {
        $work = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
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
    $json = '{"default": true, "argv": ["chlaude-peer", "--model", "default"], "ready": ["Claude Code"], "busy": ["esc to interrupt"], "transcript": {"kind": "claude-jsonl", "root": "{home}/.claude/projects"}}'
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
        $env:PATH = "$ToolsDir;$env:PATH"
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
