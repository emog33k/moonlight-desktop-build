<#
New keys for Sunshine on this PC: Sunshine makes a new certificate and key, every
paired device is forgotten, and Moonlight Desktop Agent gets a new certificate signed with
the new key.

What it does (asks for administrator rights once):
  1. Stops Sunshine (a running stream ends).
  2. Sets the old certificate and key aside, and removes all paired devices from
     sunshine_state.json (the web UI login and the host's id stay).
  3. Starts Sunshine, which makes a new certificate and key, and checks they are new.
     If anything fails, the old files are put back and Sunshine is started again.
  4. Deletes the old key, gives the agent a new certificate and restarts it.

Afterwards pair the laptop again: Moonlight > the PC > enter the PIN in Sunshine's
web UI (https://localhost:47990 > PIN).

  -DryRun   show what would be done, change nothing
#>
param(
    [switch]$DryRun,
    [switch]$Elevated,      # internal: the elevated part
    [string]$UserSid,       # internal: SID of the user who started it
    [string]$LogFile        # internal: where the elevated part writes its output
)
$ErrorActionPreference = 'Stop'

$Service    = 'SunshineService'
$ConfigDir  = Join-Path $env:ProgramFiles 'Sunshine\config'
$CredDir    = Join-Path $ConfigDir 'credentials'
$Cert       = Join-Path $CredDir 'cacert.pem'
$Key        = Join-Path $CredDir 'cakey.pem'
$StateFile  = Join-Path $ConfigDir 'sunshine_state.json'
$AgentDir   = Join-Path $env:ProgramFiles 'Moonlight Desktop Agent'
$AgentExe   = Join-Path $AgentDir 'MoonlightDesktopAgent.exe'
$AgentData  = Join-Path $env:ProgramData 'Moonlight Desktop Agent'
$PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$Suffix     = '.before-rotation'

function Step($text) { Write-Host "  - $text" }

function Stop-OurAgent {
    $session = (Get-Process -Id $PID).SessionId
    foreach ($a in @(Get-Process MoonlightDesktopAgent -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session })) {
        Stop-Process -Id $a.Id -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $a.Id -Timeout 10 -ErrorAction SilentlyContinue
    }
}

$me = [Security.Principal.WindowsIdentity]::GetCurrent()

if (-not $Elevated) {
    if (-not (Test-Path -LiteralPath $Cert) -or -not (Test-Path -LiteralPath $StateFile)) {
        throw "Sunshine is not installed in the standard folder ($ConfigDir)."
    }
    if (-not (Get-Service $Service -ErrorAction SilentlyContinue)) {
        throw "The $Service service was not found."
    }
    Write-Host "New Sunshine keys$(if ($DryRun) {' (dry run: nothing is changed)'})"
    if ($DryRun) {
        & $PowerShell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Elevated -UserSid $me.User.Value -DryRun
        Step "restart Moonlight Desktop Agent"
        exit $LASTEXITCODE
    }
    $elevLog = Join-Path $env:TEMP ("localrdp-rotate-" + [guid]::NewGuid().ToString('N') + ".log")
    $elevArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated',
                  '-UserSid', $me.User.Value, '-LogFile', "`"$elevLog`"")
    try {
        $p = Start-Process $PowerShell -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList $elevArgs
        if (Test-Path $elevLog) { Get-Content $elevLog; Remove-Item $elevLog -ErrorAction SilentlyContinue }
        if ($p.ExitCode -ne 0) { throw "The administrator part failed (exit $($p.ExitCode)); see the lines above." }
    }
    finally {
        # The elevated part stops the agent to replace its certificate: whatever
        # happened, start it again (with the new certificate if it was made)
        if (Test-Path $AgentExe) {
            Step "restart Moonlight Desktop Agent (it loads its new certificate)"
            Stop-OurAgent
            Start-Process -FilePath $AgentExe -WorkingDirectory $AgentDir
        }
    }
    Write-Host "Done. Pair the laptop again: Moonlight > the PC > PIN in https://localhost:47990" -ForegroundColor Green
    exit 0
}

# ---- Elevated part ----
if ($LogFile) { Start-Transcript -Path $LogFile -Force | Out-Null }
function Finish([int]$code) {
    if ($LogFile) { Stop-Transcript | Out-Null }
    exit $code
}
$isAdmin = (New-Object Security.Principal.WindowsPrincipal $me).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $DryRun -and -not $isAdmin) { Write-Host 'ERROR: must run as administrator.'; Finish 1 }
# The agent's key is encrypted for the user who started this (DPAPI)
if ($me.User.Value -ne $UserSid) {
    Write-Host 'ERROR: administrator rights were given by a different Windows account.'
    Finish 1
}

if ($DryRun) {
    Step "stop $Service"
    Step "set aside $Cert and $Key, remove the paired devices from $StateFile"
    Step "start $Service and wait for the new certificate and key"
    Step "delete the old key, give the agent a new certificate in $AgentData"
    Finish 0
}

function Wait-SunshineStopped {
    Stop-Service $Service -Force
    (Get-Service $Service).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
    # The service stops sunshine.exe; make sure it is gone before touching its files
    foreach ($s in @(Get-Process sunshine -ErrorAction SilentlyContinue)) {
        if (-not $s.WaitForExit(15000)) { Stop-Process -Id $s.Id -Force }
    }
}

$oldThumb = (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $Cert).Thumbprint
$moved = $false
try {
    Step "stop Sunshine"
    Wait-SunshineStopped

    Step "set the old certificate and key aside"
    Copy-Item -LiteralPath $StateFile -Destination ($StateFile + $Suffix) -Force
    Move-Item -LiteralPath $Cert -Destination ($Cert + $Suffix) -Force
    Move-Item -LiteralPath $Key -Destination ($Key + $Suffix) -Force
    $moved = $true

    Step "forget all paired devices"
    $state = Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.root) {
        $state.root.PSObject.Properties.Remove('named_devices')
        $state.root.PSObject.Properties.Remove('devices') # an older Sunshine's list
    }
    # UTF-8 without a BOM, as Sunshine writes it
    [IO.File]::WriteAllText($StateFile, ($state | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding $false))

    Step "start Sunshine (it makes a new certificate and key)"
    Start-Service $Service
    $deadline = (Get-Date).AddSeconds(60)
    while (-not ((Test-Path -LiteralPath $Cert) -and (Test-Path -LiteralPath $Key) -and
                 (Get-Item -LiteralPath $Key).Length -gt 0)) {
        if ((Get-Date) -gt $deadline) { throw 'Sunshine did not make a new certificate within 60 s.' }
        Start-Sleep -Milliseconds 500
    }
    Start-Sleep -Seconds 1 # let it finish writing
    $newThumb = (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $Cert).Thumbprint
    if ($newThumb -eq $oldThumb) { throw 'The certificate did not change.' }
    Write-Host "    new certificate: $newThumb"
}
catch {
    Write-Host "ERROR: $_"
    if ($moved) {
        Write-Host '  - putting the old certificate, key and paired devices back'
        try { Wait-SunshineStopped } catch { }
        Move-Item -LiteralPath ($Cert + $Suffix) -Destination $Cert -Force
        Move-Item -LiteralPath ($Key + $Suffix) -Destination $Key -Force
        Move-Item -LiteralPath ($StateFile + $Suffix) -Destination $StateFile -Force
    }
    try { Start-Service $Service } catch { }
    Finish 1
}

Step "delete the old key"
Remove-Item -LiteralPath ($Key + $Suffix), ($Cert + $Suffix), ($StateFile + $Suffix) -Force

if (Test-Path $AgentExe) {
    Step "give Moonlight Desktop Agent a new certificate (signed with the new key)"
    # A running agent keeps its files open, so they could not be replaced
    Stop-OurAgent
    $out = Join-Path $AgentData 'issue.txt'
    $p = Start-Process -FilePath $AgentExe -Wait -PassThru -NoNewWindow -RedirectStandardOutput $out `
        -ArgumentList @('--issue-identity', '--credentials', "`"$CredDir`"", '--out', "`"$AgentData`"")
    if (Test-Path $out) { Get-Content $out; Remove-Item $out -Force }
    if ($p.ExitCode -ne 0) {
        Write-Host "ERROR: could not make the agent certificate (exit $($p.ExitCode)). Run install-agent.ps1 again."
        Finish 1
    }
}
Finish 0
