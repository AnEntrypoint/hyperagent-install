param([int]$Port = 8787, [string]$Log)
$ErrorActionPreference = 'Stop'

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
try {
    $listener.Start()
    [IO.File]::WriteAllText($Log, 'ready')
    Start-Sleep -Seconds 3600
}
finally {
    $listener.Stop()
}
