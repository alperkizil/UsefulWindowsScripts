<#
.SYNOPSIS
    VTScanner core: hash a file with SHA-256, look it up on VirusTotal, and show results.
.DESCRIPTION
    Invoked from the right-click context menu via the registered command, or dot-sourced
    by VTScanner-ProcessPicker.ps1 which calls Invoke-VTScan directly.

    Reads its API key from %ProgramData%\VTScanner\config.json (DPAPI LocalMachine).
    Caches results in %LOCALAPPDATA%\VTScanner\cache.json (24h clean / 1h flagged TTL).
    Logs every scan to %LOCALAPPDATA%\VTScanner\scan.log.
.PARAMETER FilePath
    Absolute path to the file to scan.
#>
[CmdletBinding()]
param(
    [string]$FilePath
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security

$script:VTScannerAumid       = 'Anthropic.VTScanner'
$script:VTScannerDisplayName = 'VTScanner'
$script:VTScannerIconPath    = Join-Path $PSScriptRoot 'VTScanner.ico'
$script:VTScannerConfigPath  = Join-Path $env:ProgramData  'VTScanner\config.json'
$script:VTScannerDataDir     = Join-Path $env:LOCALAPPDATA 'VTScanner'
$script:VTScannerCachePath   = Join-Path $script:VTScannerDataDir 'cache.json'
$script:VTScannerLogPath     = Join-Path $script:VTScannerDataDir 'scan.log'
$script:VTUploadLimitBytes   = 32MB
$script:VTCleanTtl           = [TimeSpan]::FromHours(24)
$script:VTFlaggedTtl         = [TimeSpan]::FromMinutes(60)


function Initialize-VTScannerDataDir {
    if (-not (Test-Path $script:VTScannerDataDir)) {
        New-Item -ItemType Directory -Path $script:VTScannerDataDir -Force | Out-Null
    }
}

function Write-VTLog {
    param([string]$Sha256, [string]$Path, [string]$Result)
    Initialize-VTScannerDataDir
    $line = '{0} {1} "{2}" {3}' -f (Get-Date).ToUniversalTime().ToString('o'), $Sha256, $Path, $Result
    Add-Content -Path $script:VTScannerLogPath -Value $line -Encoding UTF8
}

function Read-VTApiKey {
    if (-not (Test-Path $script:VTScannerConfigPath)) {
        throw "VTScanner is not configured. Re-run Install-VTScanner.ps1 to set the API key."
    }
    $config = Get-Content -Path $script:VTScannerConfigPath -Raw | ConvertFrom-Json
    if (-not $config.apiKey) {
        throw "Config file is missing 'apiKey'."
    }
    $encrypted = [Convert]::FromBase64String($config.apiKey)
    $plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $encrypted, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)
    return [System.Text.Encoding]::UTF8.GetString($plain)
}

function Get-VTCacheTable {
    if (-not (Test-Path $script:VTScannerCachePath)) { return @{} }
    try {
        $raw = Get-Content -Path $script:VTScannerCachePath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        $tbl = @{}
        foreach ($p in $obj.PSObject.Properties) { $tbl[$p.Name] = $p.Value }
        return $tbl
    } catch {
        return @{}
    }
}

function Save-VTCacheTable {
    param([hashtable]$Table)
    Initialize-VTScannerDataDir
    ($Table | ConvertTo-Json -Depth 6) | Set-Content -Path $script:VTScannerCachePath -Encoding UTF8
}

function Test-VTCacheEntryFresh {
    param([object]$Entry)
    if (-not $Entry -or -not $Entry.fetched) { return $false }
    $fetched = [DateTime]::Parse($Entry.fetched, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
    $age = (Get-Date).ToUniversalTime() - $fetched.ToUniversalTime()
    $detections = [int]$Entry.malicious + [int]$Entry.suspicious
    $ttl = if ($detections -gt 0) { $script:VTFlaggedTtl } else { $script:VTCleanTtl }
    return $age -lt $ttl
}

function ConvertFrom-VTAttributes {
    param([object]$Attributes)
    $stats = $Attributes.last_analysis_stats
    $total = ([int]$stats.malicious + [int]$stats.suspicious +
              [int]$stats.harmless  + [int]$stats.undetected +
              [int]$stats.timeout)
    return @{
        malicious   = [int]$stats.malicious
        suspicious  = [int]$stats.suspicious
        total       = $total
        fetched     = (Get-Date).ToUniversalTime().ToString('o')
        permalink   = "https://www.virustotal.com/gui/file/$($Attributes.sha256)"
    }
}

function Invoke-VTLookup {
    param([string]$Sha256, [string]$ApiKey)
    $uri = "https://www.virustotal.com/api/v3/files/$Sha256"
    try {
        $resp = Invoke-RestMethod -Uri $uri -Headers @{ 'x-apikey' = $ApiKey } -Method Get -ErrorAction Stop
        return ConvertFrom-VTAttributes $resp.data.attributes
    } catch {
        $status = $null
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        switch ($status) {
            404     { return $null }
            401     { throw "VirusTotal rejected the API key (401). Re-run Install-VTScanner.ps1." }
            429     { throw "VirusTotal rate limit hit (429). Try again in a minute." }
            default { throw "VirusTotal request failed: $($_.Exception.Message)" }
        }
    }
}

function Invoke-VTUpload {
    param([string]$FilePath, [string]$ApiKey)
    $uri = 'https://www.virustotal.com/api/v3/files'

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $resp = Invoke-RestMethod -Uri $uri -Headers @{ 'x-apikey' = $ApiKey } `
            -Method Post -Form @{ file = Get-Item -LiteralPath $FilePath } -ErrorAction Stop
        return $resp.data.id
    }

    $boundary  = [Guid]::NewGuid().ToString('N')
    $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
    $fileName  = [System.IO.Path]::GetFileName($FilePath)
    $enc       = [System.Text.Encoding]::UTF8
    $LF        = "`r`n"
    $preamble  = "--$boundary$LF" +
                 "Content-Disposition: form-data; name=`"file`"; filename=`"$fileName`"$LF" +
                 "Content-Type: application/octet-stream$LF$LF"
    $closing   = "$LF--$boundary--$LF"

    $ms = New-Object System.IO.MemoryStream
    try {
        $preBytes   = $enc.GetBytes($preamble)
        $closeBytes = $enc.GetBytes($closing)
        $ms.Write($preBytes,   0, $preBytes.Length)
        $ms.Write($fileBytes,  0, $fileBytes.Length)
        $ms.Write($closeBytes, 0, $closeBytes.Length)
        $body = $ms.ToArray()
    } finally {
        $ms.Dispose()
    }

    $resp = Invoke-RestMethod -Uri $uri -Method Post `
        -ContentType "multipart/form-data; boundary=$boundary" `
        -Headers @{ 'x-apikey' = $ApiKey } `
        -Body $body -ErrorAction Stop
    return $resp.data.id
}

function Wait-VTAnalysis {
    param([string]$AnalysisId, [string]$ApiKey, [int]$TimeoutSeconds = 180)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $uri = "https://www.virustotal.com/api/v3/analyses/$AnalysisId"
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $resp = Invoke-RestMethod -Uri $uri -Headers @{ 'x-apikey' = $ApiKey } -Method Get -ErrorAction Stop
        if ($resp.data.attributes.status -eq 'completed') { return $true }
    }
    return $false
}

function Register-VTScannerAumid {
    $key = "HKCU:\Software\Classes\AppUserModelId\$($script:VTScannerAumid)"
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    New-ItemProperty -Path $key -Name 'DisplayName' -Value $script:VTScannerDisplayName `
        -PropertyType String -Force | Out-Null
    if (Test-Path $script:VTScannerIconPath) {
        New-ItemProperty -Path $key -Name 'IconUri' -Value $script:VTScannerIconPath `
            -PropertyType ExpandString -Force | Out-Null
    }
}

function Show-VTToast {
    param([string]$Title, [string]$Body)
    try {
        Register-VTScannerAumid

        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument,                  Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

        $iconAttr = ''
        if (Test-Path $script:VTScannerIconPath) {
            $iconUri = 'file:///' + ($script:VTScannerIconPath -replace '\\','/' -replace ' ','%20')
            $iconUriXml = [System.Security.SecurityElement]::Escape($iconUri)
            $iconAttr = "<image placement='appLogoOverride' src='$iconUriXml'/>"
        }
        $xmlString = @"
<toast>
  <visual>
    <binding template='ToastGeneric'>
      <text>$([System.Security.SecurityElement]::Escape($Title))</text>
      <text>$([System.Security.SecurityElement]::Escape($Body))</text>
      $iconAttr
    </binding>
  </visual>
</toast>
"@
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($xmlString)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($script:VTScannerAumid)
        $notifier.Show($toast)
    } catch {
        Write-Warning "Toast failed: $($_.Exception.Message)"
    }
}

function Get-VTSeverityColor {
    param([int]$Detections)
    if ($Detections -le 0) { return [System.Drawing.Color]::FromArgb(255, 30, 142, 62) }   # green
    if ($Detections -le 3) { return [System.Drawing.Color]::FromArgb(255, 200, 140, 0) }   # yellow/amber
    return [System.Drawing.Color]::FromArgb(255, 200, 50, 50)                              # red
}

function Show-VTResultsWindow {
    param(
        [string]$FilePath,
        [string]$Sha256,
        [long]  $FileSize,
        [object]$Result,
        [string]$Status                            # 'known' | 'unknown' | 'unknown-too-large'
    )

    $form              = New-Object System.Windows.Forms.Form
    $form.Text         = "VTScanner - $(Split-Path -Leaf $FilePath)"
    $form.Size         = New-Object System.Drawing.Size(560, 360)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox  = $false
    $form.MinimizeBox  = $false
    if (Test-Path $script:VTScannerIconPath) {
        $form.Icon = New-Object System.Drawing.Icon($script:VTScannerIconPath)
    }

    $pathLabel               = New-Object System.Windows.Forms.Label
    $pathLabel.Text          = "File: $FilePath"
    $pathLabel.AutoEllipsis  = $true
    $pathLabel.Location      = New-Object System.Drawing.Point(16, 14)
    $pathLabel.Size          = New-Object System.Drawing.Size(520, 20)
    $form.Controls.Add($pathLabel)

    $hashBox            = New-Object System.Windows.Forms.TextBox
    $hashBox.Text       = $Sha256
    $hashBox.ReadOnly   = $true
    $hashBox.Location   = New-Object System.Drawing.Point(16, 40)
    $hashBox.Size       = New-Object System.Drawing.Size(520, 22)
    $hashBox.Font       = New-Object System.Drawing.Font('Consolas', 9)
    $form.Controls.Add($hashBox)

    $sizeKB = [Math]::Round($FileSize / 1KB, 1)
    $sizeLabel          = New-Object System.Windows.Forms.Label
    $sizeLabel.Text     = "Size: $sizeKB KB"
    $sizeLabel.Location = New-Object System.Drawing.Point(16, 70)
    $sizeLabel.Size     = New-Object System.Drawing.Size(520, 18)
    $form.Controls.Add($sizeLabel)

    $verdictLabel              = New-Object System.Windows.Forms.Label
    $verdictLabel.Location     = New-Object System.Drawing.Point(16, 105)
    $verdictLabel.Size         = New-Object System.Drawing.Size(520, 50)
    $verdictLabel.Font         = New-Object System.Drawing.Font('Segoe UI', 22, [System.Drawing.FontStyle]::Bold)
    $verdictLabel.TextAlign    = 'MiddleCenter'

    $detailLabel              = New-Object System.Windows.Forms.Label
    $detailLabel.Location     = New-Object System.Drawing.Point(16, 165)
    $detailLabel.Size         = New-Object System.Drawing.Size(520, 40)
    $detailLabel.TextAlign    = 'MiddleCenter'
    $detailLabel.Font         = New-Object System.Drawing.Font('Segoe UI', 10)

    switch ($Status) {
        'known' {
            $detections = [int]$Result.malicious + [int]$Result.suspicious
            $verdictLabel.Text      = "$detections / $($Result.total) detections"
            $verdictLabel.ForeColor = Get-VTSeverityColor -Detections $detections
            $detailLabel.Text       = if ($detections -eq 0) {
                "No engines flagged this file."
            } elseif ($detections -le 3) {
                "$detections engine(s) raised a warning. Review on VirusTotal before trusting."
            } else {
                "$detections engines flagged this file as malicious or suspicious."
            }
        }
        'unknown' {
            $verdictLabel.Text      = 'Unknown to VirusTotal'
            $verdictLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
            $detailLabel.Text       = 'VirusTotal has no record of this file. You can upload it for analysis.'
        }
        'unknown-too-large' {
            $verdictLabel.Text      = 'Unknown to VirusTotal'
            $verdictLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
            $detailLabel.Text       = 'File exceeds the 32 MB upload limit; cannot submit for analysis.'
        }
    }
    $form.Controls.Add($verdictLabel)
    $form.Controls.Add($detailLabel)

    $btnY = 230
    $closeBtn          = New-Object System.Windows.Forms.Button
    $closeBtn.Text     = 'Close'
    $closeBtn.Size     = New-Object System.Drawing.Size(120, 32)
    $closeBtn.Location = New-Object System.Drawing.Point(420, $btnY)
    $closeBtn.Add_Click({ $form.Close() })
    $form.Controls.Add($closeBtn)
    $form.AcceptButton = $closeBtn
    $form.CancelButton = $closeBtn

    $vtUrl = "https://www.virustotal.com/gui/file/$Sha256"
    $vtBtn          = New-Object System.Windows.Forms.Button
    $vtBtn.Text     = 'View on VirusTotal'
    $vtBtn.Size     = New-Object System.Drawing.Size(160, 32)
    $vtBtn.Location = New-Object System.Drawing.Point(248, $btnY)
    $vtBtn.Add_Click({ Start-Process $vtUrl }.GetNewClosure())
    $form.Controls.Add($vtBtn)

    $script:UploadRequested = $false
    if ($Status -eq 'unknown') {
        $upBtn          = New-Object System.Windows.Forms.Button
        $upBtn.Text     = 'Upload to VirusTotal'
        $upBtn.Size     = New-Object System.Drawing.Size(160, 32)
        $upBtn.Location = New-Object System.Drawing.Point(76, $btnY)
        $upBtn.Add_Click({
            $script:UploadRequested = $true
            $form.Close()
        })
        $form.Controls.Add($upBtn)
    }

    [void]$form.ShowDialog()
    return [bool]$script:UploadRequested
}

function Invoke-VTScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Path is not a file or does not exist:`n$FilePath",
            'VTScanner', 'OK', 'Error') | Out-Null
        return
    }

    $resolved = (Resolve-Path -LiteralPath $FilePath).Path
    $info = Get-Item -LiteralPath $resolved

    try {
        $sha256 = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToLower()
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to read file for hashing:`n$($_.Exception.Message)",
            'VTScanner', 'OK', 'Error') | Out-Null
        Write-VTLog -Sha256 '?' -Path $resolved -Result "ERROR_HASH: $($_.Exception.Message)"
        return
    }

    $cache = Get-VTCacheTable
    $cached = $cache[$sha256]
    $result = $null
    $usedCache = $false

    if (Test-VTCacheEntryFresh $cached) {
        $result = $cached
        $usedCache = $true
    } else {
        try {
            $apiKey = Read-VTApiKey
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message, 'VTScanner', 'OK', 'Error') | Out-Null
            Write-VTLog -Sha256 $sha256 -Path $resolved -Result "ERROR_CONFIG: $($_.Exception.Message)"
            return
        }

        try {
            $result = Invoke-VTLookup -Sha256 $sha256 -ApiKey $apiKey
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message, 'VTScanner', 'OK', 'Error') | Out-Null
            Write-VTLog -Sha256 $sha256 -Path $resolved -Result "ERROR_LOOKUP: $($_.Exception.Message)"
            return
        }

        if ($null -ne $result) {
            $cache[$sha256] = $result
            Save-VTCacheTable -Table $cache
        }
    }

    if ($null -ne $result) {
        $detections = [int]$result.malicious + [int]$result.suspicious
        $summary = "$detections/$($result.total)"
        Show-VTToast -Title 'VTScanner' -Body "$($info.Name): $summary detections"
        Write-VTLog -Sha256 $sha256 -Path $resolved -Result "$summary$(if ($usedCache) { ' (cache)' })"
        Show-VTResultsWindow -FilePath $resolved -Sha256 $sha256 -FileSize $info.Length `
            -Result $result -Status 'known' | Out-Null
        return
    }

    if ($info.Length -gt $script:VTUploadLimitBytes) {
        Show-VTToast -Title 'VTScanner' -Body "$($info.Name): unknown to VirusTotal (>32 MB, no upload)"
        Write-VTLog -Sha256 $sha256 -Path $resolved -Result 'UNKNOWN_TOO_LARGE'
        Show-VTResultsWindow -FilePath $resolved -Sha256 $sha256 -FileSize $info.Length `
            -Result $null -Status 'unknown-too-large' | Out-Null
        return
    }

    Show-VTToast -Title 'VTScanner' -Body "$($info.Name): unknown to VirusTotal"
    Write-VTLog -Sha256 $sha256 -Path $resolved -Result 'UNKNOWN'
    $wantsUpload = Show-VTResultsWindow -FilePath $resolved -Sha256 $sha256 -FileSize $info.Length `
        -Result $null -Status 'unknown'
    if (-not $wantsUpload) { return }

    try {
        $apiKey = Read-VTApiKey
        $analysisId = Invoke-VTUpload -FilePath $resolved -ApiKey $apiKey
        $completed = Wait-VTAnalysis -AnalysisId $analysisId -ApiKey $apiKey
        if (-not $completed) {
            [System.Windows.Forms.MessageBox]::Show(
                'Upload submitted, but analysis did not finish in time. Try again later.',
                'VTScanner', 'OK', 'Information') | Out-Null
            Write-VTLog -Sha256 $sha256 -Path $resolved -Result 'UPLOAD_TIMEOUT'
            return
        }
        $fresh = Invoke-VTLookup -Sha256 $sha256 -ApiKey $apiKey
        if ($null -ne $fresh) {
            $cache = Get-VTCacheTable
            $cache[$sha256] = $fresh
            Save-VTCacheTable -Table $cache

            $detections = [int]$fresh.malicious + [int]$fresh.suspicious
            $summary = "$detections/$($fresh.total)"
            Show-VTToast -Title 'VTScanner' -Body "$($info.Name): $summary detections"
            Write-VTLog -Sha256 $sha256 -Path $resolved -Result "$summary (uploaded)"
            Show-VTResultsWindow -FilePath $resolved -Sha256 $sha256 -FileSize $info.Length `
                -Result $fresh -Status 'known' | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                'Analysis completed but VirusTotal has not indexed the result yet. Try again in a moment.',
                'VTScanner', 'OK', 'Information') | Out-Null
            Write-VTLog -Sha256 $sha256 -Path $resolved -Result 'UPLOAD_NO_INDEX'
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Upload failed:`n$($_.Exception.Message)",
            'VTScanner', 'OK', 'Error') | Out-Null
        Write-VTLog -Sha256 $sha256 -Path $resolved -Result "ERROR_UPLOAD: $($_.Exception.Message)"
    }
}


if ($MyInvocation.InvocationName -ne '.' -and $PSBoundParameters.ContainsKey('FilePath')) {
    Invoke-VTScan -FilePath $FilePath
}
