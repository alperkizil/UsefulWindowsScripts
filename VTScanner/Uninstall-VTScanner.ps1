<#
.SYNOPSIS
    Removes VTScanner: registry entries, Start Menu shortcut, install dir, and ProgramData config.
.DESCRIPTION
    Run as administrator. The per-user cache and log under %LOCALAPPDATA%\VTScanner are
    left in place by default; pass -Purge to wipe those too.
#>

[CmdletBinding()]
param(
    [switch]$Purge
)

Add-Type -AssemblyName System.Windows.Forms

$installRoot = Join-Path $env:ProgramFiles 'VTScanner'
$configDir   = Join-Path $env:ProgramData  'VTScanner'
$startMenu   = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'VTScanner'
$aumid       = 'Anthropic.VTScanner'

function Test-IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsElevated)) {
    Write-Host 'Re-launching elevated...'
    $childArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($Purge) { $childArgs += '-Purge' }
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList $childArgs
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Uninstall cancelled - elevation was denied or failed:`n$($_.Exception.Message)",
            'VTScanner', 'OK', 'Warning') | Out-Null
    }
    return
}

$confirm = [System.Windows.Forms.MessageBox]::Show(
    "Remove VTScanner from this machine?`n`nThis removes the right-click entry, the Start Menu shortcut, $installRoot, and the saved API key.",
    'VTScanner uninstall', 'YesNo', 'Question')
if ($confirm -ne 'Yes') { return }

try {
    [Microsoft.Win32.Registry]::LocalMachine.DeleteSubKeyTree('SOFTWARE\Classes\*\shell\VTScan', $false)
    Write-Host 'Removed HKLM\SOFTWARE\Classes\*\shell\VTScan'
} catch {
    Write-Warning "Could not remove right-click key: $($_.Exception.Message)"
}

try {
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree("Software\Classes\AppUserModelId\$aumid", $false)
    Write-Host "Removed HKCU\Software\Classes\AppUserModelId\$aumid"
} catch {
    Write-Warning "Could not remove AUMID key: $($_.Exception.Message)"
}

if (Test-Path $startMenu) {
    Remove-Item -Path $startMenu -Recurse -Force
    Write-Host "Removed $startMenu"
}

if (Test-Path $installRoot) {
    Remove-Item -Path $installRoot -Recurse -Force
    Write-Host "Removed $installRoot"
}

if (Test-Path $configDir) {
    Remove-Item -Path $configDir -Recurse -Force
    Write-Host "Removed $configDir"
}

if ($Purge) {
    $userData = Join-Path $env:LOCALAPPDATA 'VTScanner'
    if (Test-Path $userData) {
        Remove-Item -Path $userData -Recurse -Force
        Write-Host "Removed $userData (cache + log)"
    }
}

[System.Windows.Forms.MessageBox]::Show(
    "VTScanner has been uninstalled.$(if (-not $Purge) { "`n`nPer-user cache and log under %LOCALAPPDATA%\VTScanner were left in place." })",
    'VTScanner', 'OK', 'Information') | Out-Null
