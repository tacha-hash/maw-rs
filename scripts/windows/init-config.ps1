param(
    [string]$MawHome = (Join-Path $env:LOCALAPPDATA 'maw'),
    [string]$Node = 'nudee',
    [string]$Oracle = 'suea'
)
$ErrorActionPreference = 'Stop'
$directory = Join-Path $MawHome 'config'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$path = Join-Path $directory 'maw.config.json'
if (Test-Path -LiteralPath $path) { throw "Config already exists; edit it without replacing secrets: $path" }
$config = @{
    node = $Node; oracle = $Oracle; agents = @{}; sessions = @{}
    bind = '0.0.0.0'; port = 3458; defaultEngine = 'codex'
}
$config.agents[$Oracle] = $Node
$config.sessions[$Oracle] = $Oracle
[IO.File]::WriteAllText($path, ($config | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
Write-Output "Created $path without credentials; provision federationToken separately over a secure channel."
