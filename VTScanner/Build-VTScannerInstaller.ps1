<#
.SYNOPSIS
    Builds VTScanner-Setup.exe — a single-file, self-contained installer.
.DESCRIPTION
    Run this script ONCE on a Windows box to produce VTScanner-Setup.exe.
    The output .exe contains every VTScanner script embedded inside a CAB.
    Double-clicking the .exe extracts the bundle to a temp folder, then runs
    Install-VTScanner.ps1 (which self-elevates and walks the user through the
    rest of the install).

    Built with IExpress (iexpress.exe), which ships with every Windows
    install — no third-party tooling required.

.PARAMETER OutputPath
    Where to write VTScanner-Setup.exe. Defaults to the parent of this script.
#>

[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'VTScanner-Setup.exe')
)

$ErrorActionPreference = 'Stop'

$source = $PSScriptRoot
$files = @(
    'VTScanner.ps1',
    'VTScanner-ProcessPicker.ps1',
    'Install-VTScanner.ps1',
    'Uninstall-VTScanner.ps1',
    'New-VTScannerIcon.ps1'
)

foreach ($f in $files) {
    $p = Join-Path $source $f
    if (-not (Test-Path $p)) { throw "Missing source file: $p" }
}

$iexpress = Join-Path $env:WINDIR 'System32\iexpress.exe'
if (-not (Test-Path $iexpress)) { throw "iexpress.exe not found at $iexpress" }

$outputAbs = [System.IO.Path]::GetFullPath($OutputPath)
$outputDir = Split-Path -Parent $outputAbs
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$sed = New-TemporaryFile
$sedPath = [System.IO.Path]::ChangeExtension($sed.FullName, '.sed')
Move-Item -Path $sed.FullName -Destination $sedPath -Force

$fileEntries     = ($files | ForEach-Object { 'FILE{0}="{1}"' -f ($files.IndexOf($_)), $_ }) -join "`r`n"
$sourceMappings  = ($files | ForEach-Object { '%FILE{0}%=' -f ($files.IndexOf($_))         }) -join "`r`n"

$sedContent = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=I
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$outputAbs
FriendlyName=VTScanner Setup
AppLaunched=powershell.exe -NoProfile -ExecutionPolicy Bypass -File Install-VTScanner.ps1
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
$fileEntries
[SourceFiles]
SourceFiles0=$source
[SourceFiles0]
$sourceMappings
"@

Set-Content -Path $sedPath -Value $sedContent -Encoding ASCII

Write-Host "SED written to $sedPath"
Write-Host "Building $outputAbs ..."

$proc = Start-Process -FilePath $iexpress -ArgumentList @('/N', "`"$sedPath`"") -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -ne 0) {
    throw "iexpress failed with exit code $($proc.ExitCode). Inspect $sedPath."
}

Remove-Item -Path $sedPath -Force -ErrorAction SilentlyContinue

if (-not (Test-Path $outputAbs)) {
    throw "iexpress reported success but $outputAbs is missing."
}

Write-Host "Built: $outputAbs"
Write-Host ""
Write-Host "Distribute this single .exe. On double-click, it extracts the bundled scripts"
Write-Host "to a temp folder and runs Install-VTScanner.ps1, which prompts for elevation"
Write-Host "and walks the user through entering their VirusTotal API key."
