<#
.SYNOPSIS
    Recursively scans files in a selected directory and computes SHA-256 hashes.

.DESCRIPTION
    This script opens a folder selection dialog (defaulting to the Documents folder),
    then recursively scans all files in the selected directory and subdirectories,
    computing the SHA-256 hash for each file. Results are displayed and optionally
    exported to a CSV file.

.EXAMPLE
    .\Get-FileHashRecursive.ps1
    Opens a folder browser, scans selected folder, and displays file hashes.

.NOTES
    Author: UsefulWindowsScripts
    Requires: PowerShell 3.0 or later
#>

# Add required assemblies for folder browser dialog
Add-Type -AssemblyName System.Windows.Forms

# Function to show folder browser dialog
function Select-Folder {
    param(
        [string]$Description = "Select a folder to scan",
        [string]$InitialDirectory = [Environment]::GetFolderPath("MyDocuments")
    )

    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = $Description
    $folderBrowser.SelectedPath = $InitialDirectory
    $folderBrowser.ShowNewFolderButton = $false

    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $folderBrowser.SelectedPath
    }
    return $null
}

# Function to compute SHA-256 hash for files recursively
function Get-FileHashRecursive {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    Write-Host "`nScanning directory: $Path" -ForegroundColor Cyan
    Write-Host "Computing SHA-256 hashes for all files..." -ForegroundColor Cyan
    Write-Host ("-" * 80) -ForegroundColor Gray

    # Initialize counters
    $fileCount = 0
    $errorCount = 0
    $results = @()

    # Get all files recursively
    try {
        $files = Get-ChildItem -Path $Path -File -Recurse -ErrorAction SilentlyContinue
        $totalFiles = $files.Count

        Write-Host "Found $totalFiles files to process`n" -ForegroundColor Yellow

        foreach ($file in $files) {
            $fileCount++

            # Show progress
            if ($fileCount % 10 -eq 0 -or $fileCount -eq 1) {
                Write-Progress -Activity "Computing file hashes" `
                    -Status "Processing file $fileCount of $totalFiles" `
                    -PercentComplete (($fileCount / $totalFiles) * 100)
            }

            try {
                # Compute SHA-256 hash
                $hash = Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction Stop

                # Create result object
                $result = [PSCustomObject]@{
                    FileName = $file.Name
                    FilePath = $file.FullName
                    SHA256 = $hash.Hash
                    SizeBytes = $file.Length
                    SizeMB = [math]::Round($file.Length / 1MB, 2)
                    LastModified = $file.LastWriteTime
                }

                $results += $result

                # Display progress for first few files
                if ($fileCount -le 5) {
                    Write-Host "[$fileCount/$totalFiles] $($file.Name)" -ForegroundColor Green
                    Write-Host "  Hash: $($hash.Hash)" -ForegroundColor White
                    Write-Host "  Path: $($file.FullName)" -ForegroundColor Gray
                    Write-Host ""
                }

            } catch {
                $errorCount++
                Write-Host "ERROR processing: $($file.FullName)" -ForegroundColor Red
                Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        Write-Progress -Activity "Computing file hashes" -Completed

    } catch {
        Write-Host "ERROR: Failed to scan directory - $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }

    # Display summary
    Write-Host ("-" * 80) -ForegroundColor Gray
    Write-Host "`nScan completed!" -ForegroundColor Green
    Write-Host "Total files processed: $fileCount" -ForegroundColor White
    Write-Host "Successful: $($fileCount - $errorCount)" -ForegroundColor Green
    Write-Host "Errors: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Green" })

    return $results
}

# Main script execution
try {
    Write-Host "`n=== Recursive File Hash Scanner ===" -ForegroundColor Cyan
    Write-Host "This script will compute SHA-256 hashes for all files in a selected directory.`n" -ForegroundColor White

    # Show folder selection dialog
    $selectedPath = Select-Folder -Description "Select a folder to scan for file hashes" `
        -InitialDirectory ([Environment]::GetFolderPath("MyDocuments"))

    if ($null -eq $selectedPath) {
        Write-Host "No folder selected. Exiting..." -ForegroundColor Yellow
        exit
    }

    # Verify path exists
    if (-not (Test-Path -Path $selectedPath)) {
        Write-Host "ERROR: Selected path does not exist: $selectedPath" -ForegroundColor Red
        exit 1
    }

    # Scan files and compute hashes
    $hashResults = Get-FileHashRecursive -Path $selectedPath

    if ($null -eq $hashResults -or $hashResults.Count -eq 0) {
        Write-Host "`nNo files found or processed." -ForegroundColor Yellow
        exit
    }

    # Ask user if they want to export results
    Write-Host "`nWould you like to export results to a CSV file? (Y/N): " -ForegroundColor Cyan -NoNewline
    $export = Read-Host

    if ($export -eq 'Y' -or $export -eq 'y') {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $exportPath = Join-Path -Path $env:USERPROFILE -ChildPath "Desktop\FileHashes_$timestamp.csv"

        try {
            $hashResults | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
            Write-Host "`nResults exported to: $exportPath" -ForegroundColor Green

            # Open the CSV file
            Write-Host "Opening CSV file..." -ForegroundColor Cyan
            Start-Process $exportPath

        } catch {
            Write-Host "ERROR: Failed to export results - $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # Display sample of results
    Write-Host "`n=== Sample Results (first 10 files) ===" -ForegroundColor Cyan
    $hashResults | Select-Object -First 10 | Format-Table -AutoSize FileName, SHA256, SizeMB, LastModified

    Write-Host "`nScript completed successfully!" -ForegroundColor Green

} catch {
    Write-Host "`nFATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
