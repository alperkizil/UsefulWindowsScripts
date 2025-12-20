<#
.SYNOPSIS
    Recursively scans files in a directory and generates a detailed signature report.

.DESCRIPTION
    This script scans all files in a selected directory and its subdirectories,
    calculates SHA-256 hashes, detects duplicates, and exports results to CSV.
    Uses multi-threading for optimal performance.

.NOTES
    Compatible with PowerShell 5.1 and PowerShell 7+
    Author: Auto-generated
    Date: 2025-12-20
#>

[CmdletBinding()]
param()

# Check PowerShell version for compatibility
$PSVersion = $PSVersionTable.PSVersion.Major

Write-Host "=== File Signature Report Generator ===" -ForegroundColor Cyan
Write-Host "PowerShell Version: $PSVersion" -ForegroundColor Gray
Write-Host ""

# Function to show folder browser dialog
function Select-Folder {
    param(
        [string]$Description = "Select a folder to scan",
        [string]$InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    )

    if ($PSVersion -ge 7) {
        # PowerShell 7+ - Use Windows Forms
        Add-Type -AssemblyName System.Windows.Forms
        $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderBrowser.Description = $Description
        $folderBrowser.SelectedPath = $InitialDirectory
        $folderBrowser.ShowNewFolderButton = $false

        if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $folderBrowser.SelectedPath
        }
    }
    else {
        # PowerShell 5.1 - Use Shell.Application COM object for modern dialog
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
            $folderBrowser.Description = $Description
            $folderBrowser.SelectedPath = $InitialDirectory
            $folderBrowser.ShowNewFolderButton = $false

            if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                return $folderBrowser.SelectedPath
            }
        }
        catch {
            Write-Warning "Could not load folder browser dialog. Please enter path manually."
            $manualPath = Read-Host "Enter folder path to scan (default: $InitialDirectory)"
            if ([string]::IsNullOrWhiteSpace($manualPath)) {
                return $InitialDirectory
            }
            return $manualPath
        }
    }

    return $null
}

# Select folder to scan
$selectedPath = Select-Folder
if ([string]::IsNullOrWhiteSpace($selectedPath) -or -not (Test-Path $selectedPath)) {
    Write-Host "No valid folder selected. Exiting." -ForegroundColor Red
    exit
}

Write-Host "Selected folder: $selectedPath" -ForegroundColor Green
Write-Host ""

# Get all files recursively
Write-Host "Discovering files..." -ForegroundColor Yellow
$allFiles = Get-ChildItem -Path $selectedPath -File -Recurse -ErrorAction SilentlyContinue
$totalFiles = $allFiles.Count

if ($totalFiles -eq 0) {
    Write-Host "No files found in the selected directory." -ForegroundColor Red
    exit
}

Write-Host "Found $totalFiles files to process." -ForegroundColor Green
Write-Host ""

# Determine number of threads
$threadCount = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
Write-Host "CPU Thread Count: $threadCount" -ForegroundColor Cyan
Write-Host "Starting multi-threaded processing..." -ForegroundColor Yellow
Write-Host ""

# Initialize timing
$startTime = Get-Date

# Thread-safe collections for results and errors
$results = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
$errors = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
$processedCount = [System.Threading.Interlocked]::new()

# Process files with multi-threading
if ($PSVersion -ge 7) {
    # PowerShell 7+ - Use ForEach-Object -Parallel
    Write-Host "Using PowerShell 7+ parallel processing" -ForegroundColor Gray

    $allFiles | ForEach-Object -ThrottleLimit $threadCount -Parallel {
        $file = $_
        $results = $using:results
        $errors = $using:errors
        $totalFiles = $using:totalFiles
        $startTime = $using:startTime

        try {
            # Calculate SHA-256 hash
            $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash

            # Get file metadata
            $sizeBytes = $file.Length
            $sizeKB = [math]::Round($sizeBytes / 1KB, 2)
            $sizeMB = [math]::Round($sizeBytes / 1MB, 2)
            $sizeGB = [math]::Round($sizeBytes / 1GB, 4)

            # Create result object
            $resultObj = [PSCustomObject]@{
                SHA256            = $hash
                FileName          = $file.Name
                Directory         = $file.DirectoryName
                FileExtension     = $file.Extension
                SizeKB            = $sizeKB
                SizeMB            = $sizeMB
                SizeGB            = $sizeGB
                LastModified      = $file.LastWriteTime
                IsDuplicate       = $false
                DuplicateGroupID  = 0
            }

            $results.Add($resultObj)

            # Update progress
            $current = [System.Threading.Interlocked]::Increment([ref]$script:processedCount)
            $elapsed = (Get-Date) - $startTime
            $percentComplete = [math]::Round(($current / $totalFiles) * 100, 2)

            Write-Host "`r[Progress: $current/$totalFiles ($percentComplete%) | Elapsed: $($elapsed.ToString('hh\:mm\:ss'))] Processing: $($file.Name.PadRight(50).Substring(0,50))" -NoNewline
        }
        catch {
            $errorObj = [PSCustomObject]@{
                FilePath = $file.FullName
                Error    = $_.Exception.Message
            }
            $errors.Add($errorObj)

            $current = [System.Threading.Interlocked]::Increment([ref]$script:processedCount)
        }
    }
}
else {
    # PowerShell 5.1 - Use Runspaces
    Write-Host "Using PowerShell 5.1 runspace processing" -ForegroundColor Gray

    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $threadCount)
    $runspacePool.Open()

    $scriptBlock = {
        param($file, $results, $errors)

        try {
            # Calculate SHA-256 hash
            $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash

            # Get file metadata
            $sizeBytes = $file.Length
            $sizeKB = [math]::Round($sizeBytes / 1KB, 2)
            $sizeMB = [math]::Round($sizeBytes / 1MB, 2)
            $sizeGB = [math]::Round($sizeBytes / 1GB, 4)

            # Create result object
            $resultObj = [PSCustomObject]@{
                SHA256            = $hash
                FileName          = $file.Name
                Directory         = $file.DirectoryName
                FileExtension     = $file.Extension
                SizeKB            = $sizeKB
                SizeMB            = $sizeMB
                SizeGB            = $sizeGB
                LastModified      = $file.LastWriteTime
                IsDuplicate       = $false
                DuplicateGroupID  = 0
            }

            $results.Add($resultObj)
            return @{Success = $true}
        }
        catch {
            $errorObj = [PSCustomObject]@{
                FilePath = $file.FullName
                Error    = $_.Exception.Message
            }
            $errors.Add($errorObj)
            return @{Success = $false}
        }
    }

    $jobs = @()
    foreach ($file in $allFiles) {
        $powershell = [powershell]::Create().AddScript($scriptBlock).AddArgument($file).AddArgument($results).AddArgument($errors)
        $powershell.RunspacePool = $runspacePool

        $jobs += [PSCustomObject]@{
            PowerShell = $powershell
            Handle     = $powershell.BeginInvoke()
            File       = $file
        }
    }

    # Monitor progress
    $completed = 0
    while ($completed -lt $totalFiles) {
        $completed = ($jobs | Where-Object { $_.Handle.IsCompleted }).Count
        $elapsed = (Get-Date) - $startTime
        $percentComplete = [math]::Round(($completed / $totalFiles) * 100, 2)

        $currentFile = "Processing files..."
        if ($completed -lt $totalFiles) {
            $runningJob = $jobs | Where-Object { -not $_.Handle.IsCompleted } | Select-Object -First 1
            if ($runningJob) {
                $currentFile = $runningJob.File.Name.PadRight(50).Substring(0,50)
            }
        }

        Write-Host "`r[Progress: $completed/$totalFiles ($percentComplete%) | Elapsed: $($elapsed.ToString('hh\:mm\:ss'))] $currentFile" -NoNewline
        Start-Sleep -Milliseconds 100
    }

    # Cleanup
    foreach ($job in $jobs) {
        $job.PowerShell.EndInvoke($job.Handle)
        $job.PowerShell.Dispose()
    }

    $runspacePool.Close()
    $runspacePool.Dispose()
}

Write-Host ""
Write-Host ""

# Convert results to array and detect duplicates
Write-Host "Processing results and detecting duplicates..." -ForegroundColor Yellow
$resultsArray = $results.ToArray()

# Group by hash to find duplicates
$hashGroups = $resultsArray | Group-Object -Property SHA256 | Where-Object { $_.Count -gt 1 }

$duplicateGroupCounter = 1
foreach ($group in $hashGroups) {
    foreach ($item in $group.Group) {
        $item.IsDuplicate = $true
        $item.DuplicateGroupID = $duplicateGroupCounter
    }
    $duplicateGroupCounter++
}

# Sort results by directory and filename
$resultsArray = $resultsArray | Sort-Object Directory, FileName

# Generate output filename
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputPath = Join-Path -Path $selectedPath -ChildPath "FileSignatureReport_$timestamp.csv"

# Export to CSV
Write-Host "Exporting results to CSV..." -ForegroundColor Yellow
$resultsArray | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8

# Calculate statistics
$endTime = Get-Date
$totalTime = $endTime - $startTime
$successCount = $resultsArray.Count
$errorCount = $errors.Count
$duplicateFileCount = ($resultsArray | Where-Object { $_.IsDuplicate -eq $true }).Count
$duplicateGroupCount = $duplicateGroupCounter - 1

# Display summary
Write-Host ""
Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total files scanned: $totalFiles" -ForegroundColor Green
Write-Host "Successfully processed: $successCount" -ForegroundColor Green
Write-Host "Files with errors (skipped): $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Yellow" } else { "Green" })
Write-Host "Duplicate files found: $duplicateFileCount (in $duplicateGroupCount groups)" -ForegroundColor $(if ($duplicateFileCount -gt 0) { "Yellow" } else { "Green" })
Write-Host "Total time elapsed: $($totalTime.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
Write-Host "Report saved to: $outputPath" -ForegroundColor Green
Write-Host ""

# Display skipped files if any
if ($errorCount -gt 0) {
    Write-Host "=== SKIPPED FILES ===" -ForegroundColor Yellow
    $errorArray = $errors.ToArray()
    foreach ($err in $errorArray) {
        Write-Host "  - $($err.FilePath)" -ForegroundColor Red
        Write-Host "    Error: $($err.Error)" -ForegroundColor Gray
    }
    Write-Host ""
}

# Open CSV file
Write-Host "Opening report..." -ForegroundColor Yellow
try {
    Invoke-Item -Path $outputPath
    Write-Host "Report opened successfully!" -ForegroundColor Green
}
catch {
    Write-Warning "Could not automatically open the report. Please open it manually: $outputPath"
}

Write-Host ""
Write-Host "=== COMPLETE ===" -ForegroundColor Cyan
