$ErrorActionPreference = 'Stop'
$config = Join-Path $env:USERPROFILE '.claude.json'
$commandName = if ($args.Count -gt 0) { $args[0] } else { '' }
$subcommand = if ($args.Count -gt 1) { $args[1] } else { '' }
$rest = if ($args.Count -gt 2) { $args[2..($args.Count - 1)] } else { @() }
switch ("$commandName $subcommand") {
    'mcp add' {
        $lines = @()
        $commandLine = ''
        for ($i = 0; $i -lt $rest.Count; $i++) {
            if ($rest[$i] -eq '-e' -and $i + 1 -lt $rest.Count) {
                $lines += $rest[$i + 1]
                $i++
            } elseif ($rest[$i] -eq '--') {
                $commandLine = ($rest[($i + 1)..($rest.Count - 1)] -join ' ')
                break
            }
        }
        $lines += "COMMAND=$commandLine"
        [IO.File]::WriteAllLines($config, $lines)
        Write-Host "Added stdio MCP server hyperagent with command: $commandLine to user config"
    }
    'mcp get' {
        if (-not (Test-Path $config)) { throw 'No MCP server hyperagent found' }
        Write-Host 'hyperagent:'
        Write-Host '  Scope: User config'
        Write-Host '  Status: Connected'
        Write-Host '  Environment:'
        foreach ($line in [IO.File]::ReadAllLines($config)) {
            if ($line -notlike 'COMMAND=*') { Write-Host "    $line" }
        }
    }
    'mcp list' {
        if (-not (Test-Path $config)) { throw 'hyperagent: Failed to connect' }
        Write-Host 'hyperagent: - Connected'
    }
    'mcp remove' {
        Remove-Item -LiteralPath $config -Force -ErrorAction SilentlyContinue
        Write-Host 'Removed MCP server hyperagent from user config'
    }
    default { Write-Host 'claude stub: unsupported command'; exit 2 }
}
