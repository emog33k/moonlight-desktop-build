<#
Installs (or updates) Moonlight Desktop Agent on this PC.

What it does:
  1. Copies the agent to "C:\Program Files\Moonlight Desktop Agent" (stopping a running
     agent of this user first).
  2. Gives the agent its own certificate, signed with Sunshine's key (Moonlight
     trusts what Sunshine signs), and a key of its own, encrypted with DPAPI for
     the current Windows user, in "%ProgramData%\Moonlight Desktop Agent" (readable only by
     that user and SYSTEM). Sunshine's own key stays where it is.
  3. Allows TCP 48100 in the firewall from the local subnet and Tailscale only (any
     network profile: Windows often marks a home network as Public), for the agent only.
  4. Starts the agent at sign-in (HKCU Run) and starts it now (not elevated).

Run normally; it asks for administrator rights (UAC) for steps 1-3.
  -DryRun   show what would be done, change nothing
#>
param(
    [switch]$DryRun,
    [switch]$Elevated,          # internal: the elevated part
    [string]$UserSid,           # internal: SID of the user who started the install
    [string]$LogFile,           # internal: where the elevated part writes its output
    [string]$Source = (Join-Path $PSScriptRoot '..\moonlight-qt\build\agent-deploy')
)
$ErrorActionPreference = 'Stop'

$InstallDir  = Join-Path $env:ProgramFiles 'Moonlight Desktop Agent'
$DataDir     = Join-Path $env:ProgramData 'Moonlight Desktop Agent'
$Exe         = Join-Path $InstallDir 'MoonlightDesktopAgent.exe'
$SunshineCfg = Join-Path $env:ProgramFiles 'Sunshine\config'
$RuleName    = 'Moonlight Desktop Agent (TCP 48100, local network)'
# Who may reach the agent: the local subnet, and Tailscale (Sunshine counts these
# as its LAN too). The agent still accepts only clients paired in Sunshine.
$RemoteAddresses = @('LocalSubnet', '100.64.0.0/10', 'fd7a:115c:a1e0::/48')
# Earlier names of this rule (removed on update)
$OlderRuleNames  = @('Moonlight Desktop Agent (TCP 48100, local subnet)')
$RunKey      = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunValue    = 'Moonlight Desktop Agent'
# Never a "powershell" found through PATH
$PowerShell  = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
# The agent's earlier name: an update from it removes what it left
$OldName     = 'LocalRDP Agent'
$OldProcess  = 'LocalRdpAgent'
$OldRuleName = 'LocalRDP Agent (TCP 48100, local subnet)'

function Step($text) { Write-Host "  - $text" }
function Do-Or-Show([string]$text, [scriptblock]$action) {
    Step $text
    if (-not $DryRun) { & $action }
}

# Agents of this Windows session only (another user's agent is none of our business),
# also one with the earlier name (it holds the same one-agent lock)
function Stop-OurAgent {
    $session = (Get-Process -Id $PID).SessionId
    $agents = @(Get-Process MoonlightDesktopAgent, $OldProcess -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session })
    foreach ($a in $agents) {
        Stop-Process -Id $a.Id -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $a.Id -Timeout 10 -ErrorAction SilentlyContinue
    }
}

# Deletes a folder, but never through a link or junction (as administrator that
# could delete whatever it points to)
function Remove-PlainFolder([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    $item = Get-Item -LiteralPath $path -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Write-Warning "$path is not a normal folder (a link?); left as it is."
        return
    }
    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
}

# True once our agent (this exe) listens on TCP 48100, waiting up to 10 s
function Wait-AgentListening {
    for ($i = 0; $i -lt 20; $i++) {
        $owners = @(Get-NetTCPConnection -LocalPort 48100 -State Listen -ErrorAction SilentlyContinue |
                    ForEach-Object { Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue })
        if ($owners | Where-Object { $_.Path -and ($_.Path -ieq $Exe) }) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

$me = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal $me).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $Elevated) {
    # ---- Normal (non-elevated) part ----
    $Source = (Resolve-Path $Source).Path
    if (-not (Test-Path (Join-Path $Source 'MoonlightDesktopAgent.exe'))) {
        throw "Agent build not found in $Source. Run scripts\build-agent.bat first."
    }
    if (-not (Test-Path (Join-Path $SunshineCfg 'credentials\cacert.pem'))) {
        throw "Sunshine is not installed in the standard folder ($SunshineCfg)."
    }

    Write-Host "Moonlight Desktop Agent install$(if ($DryRun) {' (dry run: nothing is changed)'})"
    if ($DryRun) {
        # Same process tree, no UAC, no log file
        & $PowerShell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Elevated `
            -UserSid $me.User.Value -Source $Source -DryRun
        if ($LASTEXITCODE -ne 0) { throw "The administrator part failed (exit $LASTEXITCODE)." }
        Step "start the agent at sign-in (HKCU Run)"
        Step "start the agent now and check that it listens on TCP 48100"
        exit 0
    }

    # The elevated window closes when done, so it writes what it did to a log file
    $elevLog = Join-Path $env:TEMP ("localrdp-agent-install-" + [guid]::NewGuid().ToString('N') + ".log")
    $ok = $false
    try {
        $elevArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated',
                      '-UserSid', $me.User.Value, '-Source', "`"$Source`"", '-LogFile', "`"$elevLog`"")
        $p = Start-Process $PowerShell -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList $elevArgs
        if (Test-Path $elevLog) { Get-Content $elevLog; Remove-Item $elevLog -ErrorAction SilentlyContinue }
        if ($p.ExitCode -ne 0) { throw "The administrator part failed (exit $($p.ExitCode)); see the lines above." }

        Step "start the agent at sign-in (HKCU Run)"
        Set-ItemProperty -Path $RunKey -Name $RunValue -Value "`"$Exe`""
        # The earlier name's autostart, uninstall entry and log
        Remove-ItemProperty -Path $RunKey -Name $OldName -ErrorAction SilentlyContinue
        Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$OldName" -Recurse -ErrorAction SilentlyContinue
        Remove-PlainFolder (Join-Path $env:LOCALAPPDATA $OldName)
        $ok = $true
    }
    finally {
        # Whatever happened above (UAC cancelled, a step failed): never leave the
        # PC without a running agent if one is installed
        if (Test-Path $Exe) {
            $session = (Get-Process -Id $PID).SessionId
            $running = @(Get-Process MoonlightDesktopAgent -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session })
            if ($running.Count -eq 0) {
                Step "start the agent now"
                Start-Process -FilePath $Exe -WorkingDirectory $InstallDir
            }
        }
    }

    $log = Join-Path $env:LOCALAPPDATA 'Moonlight Desktop Agent\agent.log'
    if ($ok -and (Wait-AgentListening)) {
        Write-Host "Moonlight Desktop Agent is running and listening on TCP 48100." -ForegroundColor Green
        exit 0
    }
    Write-Warning "The agent is not listening. Last log lines:"
    if (Test-Path $log) { Get-Content $log -Tail 10 }
    exit 1
}

# ---- Elevated part ----
if ($LogFile) { Start-Transcript -Path $LogFile -Force | Out-Null }
trap {
    Write-Host "ERROR: $_"
    if ($LogFile) { Stop-Transcript | Out-Null }
    exit 1
}
if (-not $isAdmin -and -not $DryRun) { throw 'The elevated part must run as administrator.' }
# DPAPI "current user" must be the person who started the install, or the agent
# (running as that person) could not read its key.
if ($me.User.Value -ne $UserSid) {
    throw "Administrator rights were given by a different Windows account. Sign in as an administrator user and run the install again."
}

Do-Or-Show "stop the running agent and copy the new one to $InstallDir" {
    Stop-OurAgent
    New-Item -ItemType Directory -Force $InstallDir | Out-Null
    Copy-Item -Path (Join-Path $Source '*') -Destination $InstallDir -Recurse -Force
}

Do-Or-Show "make the agent's own certificate (signed with Sunshine's key) in $DataDir" {
    # Never follow a link someone planted there (rights and files would land elsewhere)
    if (-not (Test-Path -LiteralPath $DataDir)) { New-Item -ItemType Directory $DataDir | Out-Null }
    $item = Get-Item -LiteralPath $DataDir -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "$DataDir is not a normal folder (a link?). Remove it and run the install again."
    }
    # Replace all access rules: owner Administrators, only this user and SYSTEM, nothing
    # inherited and nothing left over from whoever may have created the folder before.
    # The folder is kept, so the current certificate stays usable if a step below fails.
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetOwner((New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544'))
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @($UserSid, 'S-1-5-18')) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            (New-Object System.Security.Principal.SecurityIdentifier $sid), 'FullControl',
            'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $DataDir -AclObject $acl

    # The agent itself does it (it reads Sunshine's key only now, as administrator)
    $out = Join-Path $DataDir 'issue.txt'
    $p = Start-Process -FilePath $Exe -Wait -PassThru -NoNewWindow -RedirectStandardOutput $out `
        -ArgumentList @('--issue-identity', '--credentials', "`"$(Join-Path $SunshineCfg 'credentials')`"", '--out', "`"$DataDir`"")
    if (Test-Path $out) { Get-Content $out; Remove-Item $out -Force }
    if ($p.ExitCode -ne 0) { throw "Could not make the agent certificate (exit $($p.ExitCode))." }
}

Do-Or-Show "allow TCP 48100 for the agent from the local network and Tailscale" {
    foreach ($name in @($RuleName) + $OlderRuleNames) {
        Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    }
    New-NetFirewallRule -DisplayName $RuleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort 48100 `
        -Profile Any -RemoteAddress $RemoteAddresses -Program $Exe | Out-Null
}

Do-Or-Show "remove what the agent left under its earlier name ($OldName)" {
    Get-NetFirewallRule -DisplayName $OldRuleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Remove-PlainFolder (Join-Path $env:ProgramFiles $OldName)
    Remove-PlainFolder (Join-Path $env:ProgramData $OldName)
}
if ($LogFile) { Stop-Transcript | Out-Null }
exit 0
