param(
    [string]$MawHome = (Join-Path $env:LOCALAPPDATA 'maw'),
    [Parameter(Mandatory = $true)][string]$PsmuxDirectory,
    [Parameter(Mandatory = $true)][string]$MawExe,
    [string]$TaskName = 'maw native peer serve',
    [int]$Port = 3458
)
$ErrorActionPreference = 'Stop'
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this installer as administrator to configure the firewall.' }
foreach ($value in @($MawHome, $PsmuxDirectory, $MawExe)) { if ($value.Contains('"')) { throw 'Paths cannot contain quotation marks.' } }
if (-not (Test-Path -LiteralPath $MawExe) -or -not (Test-Path -LiteralPath (Join-Path $PsmuxDirectory 'tmux.exe'))) { throw 'Binary or psmux tmux.exe not found.' }
$ruleName = 'MawNativePeerTCP' + $Port
if (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue) {
    Set-NetFirewallRule -Name $ruleName -Enabled True -Direction Inbound -Action Allow -Profile Any -Protocol TCP -LocalPort $Port -RemoteAddress '100.64.0.0/10' | Out-Null
} else {
    New-NetFirewallRule -Name $ruleName -DisplayName "maw peer TCP $Port Tailscale" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -RemoteAddress '100.64.0.0/10' -Profile Any | Out-Null
}
$launcher = Join-Path $MawHome 'start-native-peer.ps1'
New-Item -ItemType Directory -Path $MawHome -Force | Out-Null
$start = Join-Path $PSScriptRoot 'start-serve.ps1'
$lines = @(
    ('$env:MAW_EXE = ' + "'" + $MawExe.Replace("'", "''") + "'")
    ('& ' + "'" + $start.Replace("'", "''") + "' -MawHome '" + $MawHome.Replace("'", "''") + "' -PsmuxDirectory '" + $PsmuxDirectory.Replace("'", "''") + "' -Port " + $Port)
)
[IO.File]::WriteAllLines($launcher, $lines, [Text.UTF8Encoding]::new($false))
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $launcher + '"')
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$taskPrincipal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $taskPrincipal -Force | Out-Null
Write-Output "Installed $TaskName for $user; TCP $Port restricted to 100.64.0.0/10."
