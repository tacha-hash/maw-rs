[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$MawHome = $env:MAW_HOME,
    [string]$PsmuxDirectory = $env:MAW_PSMUX_DIR,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Arguments
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $MawHome) { $MawHome = Join-Path $env:LOCALAPPDATA 'maw' }
if (-not $PsmuxDirectory -or -not (Test-Path -LiteralPath (Join-Path $PsmuxDirectory 'tmux.exe'))) {
    throw 'Set MAW_PSMUX_DIR to the psmux directory containing its tmux.exe compatibility executable.'
}
$env:MAW_HOME = $MawHome
$env:TERM = 'xterm-256color'
$env:PATH = $PsmuxDirectory + ';' + $env:PATH
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$exe = Join-Path $repo 'target\debug\maw-rs.exe'
if ($env:MAW_EXE) { $exe = $env:MAW_EXE }
if (-not (Test-Path -LiteralPath $exe)) { throw "Native binary not found: $exe" }
& $exe @Arguments
exit $LASTEXITCODE
