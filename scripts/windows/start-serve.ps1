param(
    [string]$MawHome = $env:MAW_HOME,
    [string]$PsmuxDirectory = $env:MAW_PSMUX_DIR,
    [int]$Port = 3458
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $MawHome) { $MawHome = Join-Path $env:LOCALAPPDATA 'maw' }
if (-not $PsmuxDirectory -or -not (Test-Path -LiteralPath (Join-Path $PsmuxDirectory 'tmux.exe'))) {
    throw 'Set MAW_PSMUX_DIR to the psmux directory containing tmux.exe.'
}
$env:MAW_HOME = $MawHome
$env:TERM = 'xterm-256color'
$env:PATH = $PsmuxDirectory + ';' + $env:PATH
$exe = Join-Path $repo 'target\debug\maw-rs.exe'
if ($env:MAW_EXE) { $exe = $env:MAW_EXE }
if (-not (Test-Path -LiteralPath $exe)) { throw "Native binary not found: $exe" }
try {
    $info = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/info" -TimeoutSec 2
    $config = Get-Content -LiteralPath (Join-Path $MawHome 'config\maw.config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($info.node -ne $config.node -or $info.oracle -ne $config.oracle) { throw 'Port belongs to another identity.' }
    Write-Output "Already serving $($info.node)/$($info.oracle) on $Port"
    exit 0
} catch {
    if ($_.Exception.Message -eq 'Port belongs to another identity.') { throw }
}
$logs = Join-Path $MawHome 'logs'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$process = Start-Process -FilePath $exe -ArgumentList "serve --host 0.0.0.0 --port $Port" -WorkingDirectory $repo -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs 'serve.stdout.log') -RedirectStandardError (Join-Path $logs 'serve.stderr.log')
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 300
    $process.Refresh()
    if ($process.HasExited) { throw "Serve exited: $($process.ExitCode). See $logs" }
    try { $null = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/info" -TimeoutSec 2; Write-Output "Serve ready on $Port"; exit 0 } catch {}
}
throw "Serve did not become ready. See $logs"
