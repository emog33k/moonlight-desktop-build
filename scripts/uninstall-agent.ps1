<#
Removes Moonlight Desktop Agent from this PC: stops it, removes autostart, the firewall rule,
the program folder and the agent's certificate/key.
  -DryRun   show what would be done, change nothing
#>
param([switch]$DryRun, [switch]$Elevated)
$ErrorActionPreference = 'Stop'

$InstallDir = Join-Path $env:ProgramFiles 'Moonlight Desktop Agent'
$DataDir    = Join-Path $env:ProgramData 'Moonlight Desktop Agent'
$RuleName   = 'Moonlight Desktop Agent (TCP 48100, local network)'
$RunKey     = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
# The agent's earlier name (an install that was never updated)
$OldName    = 'LocalRDP Agent'

function Do-Or-Show([string]$text, [scriptblock]$action) {
    Write-Host "  - $text"
    if (-not $DryRun) { & $action }
}

# Deletes a folder, but never through a link or junction
function Remove-PlainFolder([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    $item = Get-Item -LiteralPath $path -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Write-Warning "$path is not a normal folder (a link?); left as it is."
        return
    }
    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not $Elevated) {
    Write-Host "Moonlight Desktop Agent uninstall$(if ($DryRun) {' (dry run: nothing is changed)'})"
    Do-Or-Show "stop the agent" {
        # This Windows session's agent only
        $session = (Get-Process -Id $PID).SessionId
        foreach ($a in @(Get-Process MoonlightDesktopAgent, LocalRdpAgent -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session })) {
            Stop-Process -Id $a.Id -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $a.Id -Timeout 10 -ErrorAction SilentlyContinue
        }
    }
    Do-Or-Show "remove autostart" {
        foreach ($name in @('Moonlight Desktop Agent', $OldName)) {
            Remove-ItemProperty -Path $RunKey -Name $name -ErrorAction SilentlyContinue
        }
    }
    $elevArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated')
    if ($DryRun) {
        & $PowerShell @($elevArgs + '-DryRun')
        if ($LASTEXITCODE -ne 0) { throw "The administrator part failed (exit $LASTEXITCODE)." }
    }
    else {
        $p = Start-Process $PowerShell -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList $elevArgs
        if ($p.ExitCode -ne 0) { throw "The administrator part failed (exit $($p.ExitCode))." }
        Write-Host "Moonlight Desktop Agent removed." -ForegroundColor Green
    }
    exit 0
}

Do-Or-Show "remove the firewall rule" {
    foreach ($rule in @($RuleName, 'Moonlight Desktop Agent (TCP 48100, local subnet)', "$OldName (TCP 48100, local subnet)")) {
        Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    }
}
Do-Or-Show "delete $InstallDir" {
    Remove-PlainFolder $InstallDir
    Remove-PlainFolder (Join-Path $env:ProgramFiles $OldName)
}
Do-Or-Show "delete $DataDir (the agent's certificate and key)" {
    Remove-PlainFolder $DataDir
    Remove-PlainFolder (Join-Path $env:ProgramData $OldName)
}
exit 0
