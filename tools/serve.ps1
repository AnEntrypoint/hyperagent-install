$ErrorActionPreference = 'Stop'
param([string]$ReleaseDir, [int]$Port, [string]$Log)

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
[IO.File]::WriteAllText($Log, 'ready')
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $relative = [Uri]::UnescapeDataString($context.Request.Url.AbsolutePath.TrimStart('/'))
        $path = Join-Path $ReleaseDir ($relative -replace '/', '\')
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $bytes = [IO.File]::ReadAllBytes($path)
            $context.Response.ContentLength64 = $bytes.Length
            $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $context.Response.StatusCode = 404
        }
        $context.Response.Close()
    }
}
finally {
    $listener.Stop()
    $listener.Close()
}
