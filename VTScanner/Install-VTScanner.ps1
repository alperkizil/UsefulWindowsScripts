<#
.SYNOPSIS
    Installs VTScanner per-machine: copies files to %ProgramFiles%\VTScanner,
    generates the icon, captures and DPAPI-encrypts the VirusTotal API key,
    registers the right-click context menu entry, and creates a Start Menu
    shortcut for the process picker.
.DESCRIPTION
    Run as administrator. Requires Windows 10 (PowerShell 5.1 or newer).
#>

[CmdletBinding()] param()

$VTLogPath = Join-Path $env:PUBLIC 'VTScanner-install.log'
function Write-VTInstallLog {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date).ToString('o'), $Message
    try { Add-Content -LiteralPath $VTLogPath -Value $line -Encoding UTF8 -ErrorAction Stop } catch {}
}
Write-VTInstallLog "=== Install-VTScanner.ps1 entered ==="
Write-VTInstallLog "PSCommandPath=$PSCommandPath"
Write-VTInstallLog "PSScriptRoot=$PSScriptRoot"
Write-VTInstallLog "User=$env:USERNAME Domain=$env:USERDOMAIN PSVersion=$($PSVersionTable.PSVersion)"

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Security
    Write-VTInstallLog 'Loaded WinForms / Drawing / Security assemblies'
} catch {
    Write-VTInstallLog "ASSEMBLY LOAD FAILED: $($_.Exception.Message)"
    throw
}

$installRoot = Join-Path $env:ProgramFiles 'VTScanner'
$configDir   = Join-Path $env:ProgramData 'VTScanner'
$configPath  = Join-Path $configDir 'config.json'
$iconPath    = Join-Path $installRoot 'VTScanner.ico'
$aumid       = 'Anthropic.VTScanner'

function Test-IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

$elevated = Test-IsElevated
Write-VTInstallLog "Elevated=$elevated"

if (-not $elevated) {
    Write-Host 'Re-launching elevated...'
    Write-VTInstallLog 'Self-elevating via Start-Process -Verb RunAs -Wait'
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', $PSCommandPath
        )
        Write-VTInstallLog 'Elevated child returned'
    } catch {
        Write-VTInstallLog "Self-elevation failed: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "Install cancelled — elevation was denied or failed:`n$($_.Exception.Message)",
            'VTScanner', 'OK', 'Warning') | Out-Null
    }
    return
}

function Show-VTApiKeyDialog {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'VTScanner — VirusTotal API Key'
    $form.Size = New-Object System.Drawing.Size(520, 230)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $info          = New-Object System.Windows.Forms.Label
    $info.Text     = "Paste your VirusTotal API key.`nGet one free at https://www.virustotal.com/gui/my-apikey"
    $info.Location = New-Object System.Drawing.Point(16, 14)
    $info.Size     = New-Object System.Drawing.Size(480, 40)
    $form.Controls.Add($info)

    $box           = New-Object System.Windows.Forms.TextBox
    $box.Location  = New-Object System.Drawing.Point(16, 64)
    $box.Size      = New-Object System.Drawing.Size(480, 22)
    $box.UseSystemPasswordChar = $true
    $form.Controls.Add($box)

    $status        = New-Object System.Windows.Forms.Label
    $status.Location = New-Object System.Drawing.Point(16, 96)
    $status.Size   = New-Object System.Drawing.Size(480, 22)
    $form.Controls.Add($status)

    $testBtn       = New-Object System.Windows.Forms.Button
    $testBtn.Text  = 'Test'
    $testBtn.Size  = New-Object System.Drawing.Size(90, 30)
    $testBtn.Location = New-Object System.Drawing.Point(16, 138)
    $form.Controls.Add($testBtn)

    $okBtn         = New-Object System.Windows.Forms.Button
    $okBtn.Text    = 'Save'
    $okBtn.Size    = New-Object System.Drawing.Size(90, 30)
    $okBtn.Location = New-Object System.Drawing.Point(308, 138)
    $okBtn.DialogResult = 'OK'
    $form.Controls.Add($okBtn)
    $form.AcceptButton = $okBtn

    $cancelBtn       = New-Object System.Windows.Forms.Button
    $cancelBtn.Text  = 'Cancel'
    $cancelBtn.Size  = New-Object System.Drawing.Size(90, 30)
    $cancelBtn.Location = New-Object System.Drawing.Point(406, 138)
    $cancelBtn.DialogResult = 'Cancel'
    $form.Controls.Add($cancelBtn)
    $form.CancelButton = $cancelBtn

    $testBtn.Add_Click({
        $key = $box.Text.Trim()
        if (-not $key) {
            $status.ForeColor = [System.Drawing.Color]::FromArgb(180, 0, 0)
            $status.Text = 'Enter a key first.'
            return
        }
        $status.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
        $status.Text = 'Testing...'
        $form.Refresh()
        try {
            $resp = Invoke-RestMethod -Uri "https://www.virustotal.com/api/v3/users/$key" `
                -Headers @{ 'x-apikey' = $key } -Method Get -ErrorAction Stop
            if ($resp.data.id) {
                $status.ForeColor = [System.Drawing.Color]::FromArgb(30, 142, 62)
                $status.Text = "OK — authenticated as $($resp.data.id)."
            } else {
                $status.ForeColor = [System.Drawing.Color]::FromArgb(200, 50, 50)
                $status.Text = 'Unexpected response from VirusTotal.'
            }
        } catch {
            $status.ForeColor = [System.Drawing.Color]::FromArgb(200, 50, 50)
            $status.Text = "Failed: $($_.Exception.Message)"
        }
    })

    $result = $form.ShowDialog()
    $value  = if ($result -eq 'OK') { $box.Text.Trim() } else { $null }
    $form.Dispose()
    return $value
}

function Save-VTApiKey {
    param([Parameter(Mandatory)][string]$ApiKey)
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($ApiKey)
    $blob  = [System.Security.Cryptography.ProtectedData]::Protect(
        $bytes, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)
    $config = [PSCustomObject]@{ apiKey = [Convert]::ToBase64String($blob) }
    ($config | ConvertTo-Json) | Set-Content -Path $configPath -Encoding UTF8
}

function Copy-VTFiles {
    if (-not (Test-Path $installRoot)) {
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
    }
    $files = @('VTScanner.ps1', 'VTScanner-ProcessPicker.ps1', 'New-VTScannerIcon.ps1', 'Uninstall-VTScanner.ps1')
    foreach ($name in $files) {
        $src = Join-Path $PSScriptRoot $name
        if (-not (Test-Path $src)) { throw "Missing source file: $src" }
        Copy-Item -Path $src -Destination (Join-Path $installRoot $name) -Force
    }
}

function Build-VTIcon {
    . (Join-Path $installRoot 'New-VTScannerIcon.ps1')
    New-VTScannerIcon -OutputPath $iconPath
}

function Register-VTContextMenu {
    $scanScript = Join-Path $installRoot 'VTScanner.ps1'
    $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scanScript`" -FilePath `"%1`""

    $base = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('SOFTWARE\Classes\*\shell\VTScan')
    try {
        $base.SetValue('',     'Scan with VirusTotal')
        $base.SetValue('Icon', $iconPath)
        $cmdKey = $base.CreateSubKey('command')
        try { $cmdKey.SetValue('', $cmd) } finally { $cmdKey.Close() }
    } finally {
        $base.Close()
    }

    $basePsPath = 'HKLM:\SOFTWARE\Classes\*\shell\VTScan'
    $cmdPsPath  = 'HKLM:\SOFTWARE\Classes\*\shell\VTScan\command'
    try {
        Set-Item       -LiteralPath $basePsPath -Value 'Scan with VirusTotal' -Force
        Set-ItemProperty -LiteralPath $basePsPath -Name 'Icon' -Value $iconPath -Force
        Set-Item       -LiteralPath $cmdPsPath  -Value $cmd -Force
        Write-VTInstallLog 'Reapplied default values via Set-Item -LiteralPath'
    } catch {
        Write-VTInstallLog "Set-Item reapply failed (non-fatal): $($_.Exception.Message)"
    }
}

function Set-VTShortcutRunAsAdmin {
    param([string]$LnkPath)
    $bytes = [System.IO.File]::ReadAllBytes($LnkPath)
    if ($bytes.Length -lt 22) { return }
    $bytes[21] = $bytes[21] -bor 0x20
    [System.IO.File]::WriteAllBytes($LnkPath, $bytes)
}

function New-VTStartMenuShortcut {
    $programs = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'VTScanner'
    if (-not (Test-Path $programs)) { New-Item -ItemType Directory -Path $programs -Force | Out-Null }
    $lnk = Join-Path $programs 'VTScanner — Scan Running Process.lnk'

    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($lnk)
    $sc.TargetPath = (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')
    $sc.Arguments  = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f `
                     (Join-Path $installRoot 'VTScanner-ProcessPicker.ps1')
    $sc.WorkingDirectory = $installRoot
    $sc.IconLocation = "$iconPath,0"
    $sc.Description  = 'Pick a running process and scan its executable on VirusTotal.'
    $sc.Save()

    Set-VTShortcutRunAsAdmin -LnkPath $lnk
}

try {
    Write-VTInstallLog 'Showing API key dialog'
    $apiKey = Show-VTApiKeyDialog
    if (-not $apiKey) {
        Write-VTInstallLog 'No API key supplied; aborting'
        return
    }

    Write-VTInstallLog "Copying files to $installRoot"
    Copy-VTFiles

    Write-VTInstallLog 'Saving API key (DPAPI LocalMachine)'
    Save-VTApiKey -ApiKey $apiKey

    Write-VTInstallLog 'Generating icon'
    Build-VTIcon

    Write-VTInstallLog 'Registering HKLM right-click entry via Microsoft.Win32.Registry'
    Register-VTContextMenu

    Write-VTInstallLog 'Creating Start Menu shortcut'
    New-VTStartMenuShortcut

    Write-VTInstallLog 'Install completed successfully'
    [System.Windows.Forms.MessageBox]::Show(
        "VTScanner installed.`n`nRight-click any file in Explorer and choose 'Scan with VirusTotal',`nor open Start → VTScanner → 'Scan Running Process'.",
        'VTScanner', 'OK', 'Information') | Out-Null
} catch {
    Write-VTInstallLog "FATAL: $($_.Exception.GetType().FullName): $($_.Exception.Message)"
    Write-VTInstallLog ($_ | Out-String)
    [System.Windows.Forms.MessageBox]::Show(
        "Install failed:`n$($_.Exception.Message)`n`nLog: $VTLogPath",
        'VTScanner', 'OK', 'Error') | Out-Null
}
