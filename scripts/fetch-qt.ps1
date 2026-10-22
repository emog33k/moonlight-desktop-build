# Downloads the minimal Qt 6 MSVC x64 SDK needed to build moonlight-qt into tools\Qt.
# aqtinstall 3.3.0 does not understand the current Qt repository layout, so we read
# the official Updates.xml (checked against download.qt.io's sha256) and verify every
# archive against its .sha1 published next to it before extracting.
param(
    [string]$Version = '6.11.3',
    [string[]]$Archives = @('qtbase', 'qtsvg', 'qtdeclarative', 'qttranslations', 'd3dcompiler_47', 'qttools')
)
# From these archives only the listed files are extracted (windeployqt needs lconvert for translations).
$PartialExtract = @{ 'qttools' = @('bin\lconvert.exe', 'bin\lrelease.exe') }
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$root = Split-Path $PSScriptRoot -Parent
$dl = Join-Path $root 'tools\downloads\qt'
$dest = Join-Path $root "tools\Qt\$Version\msvc2022_64"
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'
New-Item -ItemType Directory -Force $dl, $dest | Out-Null

$v = $Version -replace '\.', ''
$base = "https://download.qt.io/online/qtsdkrepository/windows_x86/desktop/qt6_$v/qt6_${v}_msvc2022_64/"

# The checksum published next to a file: .sha256 if the repository has it, else .sha1
# (Qt switched layouts; read raw bytes as ASCII, the server labels them oddly)
function Get-PublishedHash([string]$url) {
    foreach ($algo in @('SHA256', 'SHA1')) {
        try {
            $raw = (Invoke-WebRequest "$url.$($algo.ToLower())" -UseBasicParsing).RawContentStream.ToArray()
            return @{ Algorithm = $algo; Hash = ([Text.Encoding]::ASCII.GetString($raw) -split '\s+')[0].ToUpper() }
        }
        catch {
            if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { continue }
            throw
        }
    }
    return $null
}

# Updates.xml comes straight from download.qt.io over HTTPS; checked too when a checksum is published
Invoke-WebRequest "${base}Updates.xml" -OutFile "$dl\Updates.xml" -UseBasicParsing
$expected = Get-PublishedHash "${base}Updates.xml"
if ($expected -and (Get-FileHash "$dl\Updates.xml" -Algorithm $expected.Algorithm).Hash -ne $expected.Hash) {
    throw 'Updates.xml checksum mismatch'
}

[xml]$x = Get-Content "$dl\Updates.xml" -Raw
$pkg = $x.Updates.PackageUpdate | Where-Object { $_.Name -eq "qt.qt6.$v.win64_msvc2022_64" }
if (-not $pkg) { throw "package qt.qt6.$v.win64_msvc2022_64 not found" }

$files = ($pkg.DownloadableArchives -split ',\s*') | Where-Object {
    $name = $_
    $Archives | Where-Object { $name -like "$_-*" -or $name -like "$_*.7z" }
}
foreach ($f in $files) {
    $url = "$base$($pkg.Name)/$($pkg.Version)$f"
    $out = Join-Path $dl $f
    Write-Host "downloading $f"
    Invoke-WebRequest $url -OutFile $out -UseBasicParsing
    # Every archive must have a published checksum and match it
    $expected = Get-PublishedHash $url
    if (-not $expected) { throw "no checksum published for $f" }
    if ((Get-FileHash $out -Algorithm $expected.Algorithm).Hash -ne $expected.Hash) { throw "checksum mismatch: $f" }
    $only = $PartialExtract.Keys | Where-Object { $f -like "$_-*" } | ForEach-Object { $PartialExtract[$_] }
    & $sevenZip x $out "-o$dest" -y @($only) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "extract failed: $f" }
    Remove-Item $out
}

# Static libraries for Qt's QML language server tooling are ~1.4 GB and never linked by apps.
Get-ChildItem "$dest\lib" -File | Where-Object Name -match '^Qt6(QmlLS|QmlDom|Qmltc|QuickControlsTestUtils|QuickTestUtils|QmlCompilerPrivate)' | Remove-Item -Force

# Qt's archives ship with a placeholder prefix; qt.conf makes qmake use the real location.
$bin = Get-ChildItem $dest -Recurse -Filter qmake.exe | Select-Object -First 1
Set-Content (Join-Path $bin.DirectoryName 'qt.conf') "[Paths]`r`nPrefix=..`r`n" -Encoding ascii
Write-Host "Qt ready: $($bin.DirectoryName)"
