$ErrorActionPreference = 'Stop'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = Split-Path -Parent $toolsDir
$scanFiles = Get-ChildItem -LiteralPath $repoDir -Recurse -File | Where-Object { $_.FullName -notmatch '\\\.git\\|\\\.gm\\|\\\.agentplug' }
$tokens = $null
$errors = $null
foreach ($file in ($scanFiles | Where-Object { $_.Extension -eq '.ps1' })) {
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw "POWERSHELL SYNTAX FAIL: $($file.FullName) $($errors[0].Message)" }
}
$badPaths = @('/work' + 'space', '/config/work' + 'space', '/data/work' + 'space', '/' + 'tmp')
$modelFlag = '--' + 'model'
$tokenPrefix = 'sk-ant' + '-'
$authAssignment = 'ANTHROPIC_AUTH' + '_TOKEN='
foreach ($pattern in $badPaths) {
    $hits = Select-String -Path $scanFiles.FullName -SimpleMatch -Pattern $pattern
    if ($hits) { throw "POWERSHELL SYNTAX FAIL: hardcoded host path $pattern" }
}
$modelHits = Select-String -Path $scanFiles.FullName -SimpleMatch -Pattern $modelFlag | Where-Object { $_.Line -notlike '*default*' }
if ($modelHits) { throw 'POWERSHELL SYNTAX FAIL: conflicting model override' }
$tokenHits = Select-String -Path $scanFiles.FullName -SimpleMatch -Pattern $tokenPrefix
if ($tokenHits) { throw 'POWERSHELL SYNTAX FAIL: credential token in repository' }
$authHits = Select-String -Path $scanFiles.FullName -SimpleMatch -Pattern $authAssignment
if ($authHits) { throw 'POWERSHELL SYNTAX FAIL: credential assignment in repository' }
Write-Host 'POWERSHELL SYNTAX PASS: parser, portability and model checks'
