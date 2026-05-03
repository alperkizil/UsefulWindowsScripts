<#
.SYNOPSIS
    VTScanner process picker - Task-Manager-style list of running processes; pick one
    and scan its executable on VirusTotal.
.DESCRIPTION
    Launched from the Start Menu shortcut "VTScanner - Scan Running Process".
    The shortcut requests elevation so we can read paths of elevated processes.
    Dot-sources VTScanner.ps1 so the scan/cache/log/UI logic lives in one place.
#>

[CmdletBinding()] param()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scanScript = Join-Path $PSScriptRoot 'VTScanner.ps1'
if (-not (Test-Path $scanScript)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Cannot find VTScanner.ps1 next to the picker:`n$scanScript",
        'VTScanner', 'OK', 'Error') | Out-Null
    return
}
. $scanScript

function Get-VTProcessRows {
    $rows = @()
    Get-Process | Sort-Object -Property Name | ForEach-Object {
        $path = $null
        try { $path = $_.Path } catch { $path = $null }
        $company = ''
        $description = ''
        try { if ($_.Company)     { $company     = $_.Company } }     catch {}
        try { if ($_.Description) { $description = $_.Description } } catch {}
        $rows += [PSCustomObject]@{
            Name        = $_.Name
            PID         = $_.Id
            Company     = $company
            Description = $description
            Path        = $path
            Selectable  = [bool]$path
        }
    }
    return $rows
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'VTScanner - Scan Running Process'
$form.Size = New-Object System.Drawing.Size(900, 560)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize   = New-Object System.Drawing.Size(700, 400)
if (Test-Path $script:VTScannerIconPath) {
    $form.Icon = New-Object System.Drawing.Icon($script:VTScannerIconPath)
}

$filterLabel          = New-Object System.Windows.Forms.Label
$filterLabel.Text     = 'Filter:'
$filterLabel.Location = New-Object System.Drawing.Point(12, 16)
$filterLabel.Size     = New-Object System.Drawing.Size(50, 22)
$form.Controls.Add($filterLabel)

$filterBox            = New-Object System.Windows.Forms.TextBox
$filterBox.Location   = New-Object System.Drawing.Point(62, 12)
$filterBox.Size       = New-Object System.Drawing.Size(280, 22)
$filterBox.Anchor     = 'Top, Left'
$form.Controls.Add($filterBox)

$grid                = New-Object System.Windows.Forms.DataGridView
$grid.Location       = New-Object System.Drawing.Point(12, 44)
$grid.Size           = New-Object System.Drawing.Size(862, 432)
$grid.Anchor         = 'Top, Bottom, Left, Right'
$grid.ReadOnly       = $true
$grid.AllowUserToAddRows    = $false
$grid.AllowUserToDeleteRows = $false
$grid.RowHeadersVisible     = $false
$grid.SelectionMode  = 'FullRowSelect'
$grid.MultiSelect    = $false
$grid.AutoSizeColumnsMode   = 'Fill'
$grid.ColumnCount    = 5
$grid.Columns[0].Name = 'Name'
$grid.Columns[1].Name = 'PID'
$grid.Columns[2].Name = 'Company'
$grid.Columns[3].Name = 'Description'
$grid.Columns[4].Name = 'Path'
$grid.Columns[1].FillWeight = 40
$grid.Columns[0].FillWeight = 80
$grid.Columns[2].FillWeight = 100
$grid.Columns[3].FillWeight = 140
$grid.Columns[4].FillWeight = 240
$form.Controls.Add($grid)

$refreshBtn          = New-Object System.Windows.Forms.Button
$refreshBtn.Text     = 'Refresh'
$refreshBtn.Size     = New-Object System.Drawing.Size(100, 30)
$refreshBtn.Anchor   = 'Bottom, Right'
$refreshBtn.Location = New-Object System.Drawing.Point(540, 488)
$form.Controls.Add($refreshBtn)

$scanBtn             = New-Object System.Windows.Forms.Button
$scanBtn.Text        = 'Scan Selected'
$scanBtn.Size        = New-Object System.Drawing.Size(140, 30)
$scanBtn.Anchor      = 'Bottom, Right'
$scanBtn.Location    = New-Object System.Drawing.Point(648, 488)
$scanBtn.Enabled     = $false
$form.Controls.Add($scanBtn)

$closeBtn            = New-Object System.Windows.Forms.Button
$closeBtn.Text       = 'Close'
$closeBtn.Size       = New-Object System.Drawing.Size(100, 30)
$closeBtn.Anchor     = 'Bottom, Right'
$closeBtn.Location   = New-Object System.Drawing.Point(794, 488)
$closeBtn.Add_Click({ $form.Close() })
$form.Controls.Add($closeBtn)
$form.CancelButton   = $closeBtn

$script:AllRows = @()

function Update-VTGrid {
    param([string]$Filter)
    $grid.Rows.Clear()
    $needle = if ($Filter) { $Filter.ToLowerInvariant() } else { '' }
    foreach ($r in $script:AllRows) {
        if ($needle) {
            $hay = "$($r.Name) $($r.PID) $($r.Company) $($r.Description) $($r.Path)".ToLowerInvariant()
            if ($hay -notlike "*$needle*") { continue }
        }
        $idx = $grid.Rows.Add(@($r.Name, $r.PID, $r.Company, $r.Description, $r.Path))
        $row = $grid.Rows[$idx]
        $row.Tag = $r
        if (-not $r.Selectable) {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Gray
            $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
            foreach ($cell in $row.Cells) {
                $cell.ToolTipText = 'Path not accessible (protected or kernel process).'
            }
        }
    }
}

function Refresh-VTProcessList {
    $script:AllRows = Get-VTProcessRows
    Update-VTGrid -Filter $filterBox.Text
}

$refreshBtn.Add_Click({ Refresh-VTProcessList })

$filterBox.Add_TextChanged({ Update-VTGrid -Filter $filterBox.Text })

$grid.Add_SelectionChanged({
    $scanBtn.Enabled = $false
    if ($grid.SelectedRows.Count -gt 0) {
        $tag = $grid.SelectedRows[0].Tag
        if ($tag -and $tag.Selectable) { $scanBtn.Enabled = $true }
    }
})

$scanBtn.Add_Click({
    if ($grid.SelectedRows.Count -eq 0) { return }
    $tag = $grid.SelectedRows[0].Tag
    if (-not $tag -or -not $tag.Selectable) { return }
    try {
        Invoke-VTScan -FilePath $tag.Path
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Scan failed:`n$($_.Exception.Message)",
            'VTScanner', 'OK', 'Error') | Out-Null
    }
})

Refresh-VTProcessList
[void]$form.ShowDialog()
