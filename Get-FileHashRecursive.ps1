<#
.SYNOPSIS
    Recursively scans files in a selected directory and computes SHA-256 hashes using multi-threading.

.DESCRIPTION
    This script opens a folder selection dialog (defaulting to the Documents folder),
    then recursively scans all files in the selected directory and subdirectories,
    computing the SHA-256 hash for each file using multi-threading based on CPU cores.
    Identifies duplicate files and exports results to a CSV file.

.EXAMPLE
    .\Get-FileHashRecursive.ps1
    Opens a folder browser, scans selected folder, and displays file hashes.

.NOTES
    Author: UsefulWindowsScripts
    Requires: PowerShell 7.0 or later (for parallel processing)
    For PowerShell 5.1, falls back to single-threaded processing
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

# Function to compute SHA-256 hash for files recursively with multi-threading
function Get-FileHashRecursive {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    Write-Host "`nScanning directory: $Path" -ForegroundColor Cyan
    Write-Host "Computing SHA-256 hashes for all files..." -ForegroundColor Cyan
    Write-Host ("-" * 80) -ForegroundColor Gray

    # Get CPU thread count
    $cpuThreads = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
    Write-Host "Detected CPU threads: $cpuThreads" -ForegroundColor Yellow
    Write-Host "Using parallel processing with $cpuThreads threads`n" -ForegroundColor Yellow

    # Get all files recursively
    try {
        $files = Get-ChildItem -Path $Path -File -Recurse -ErrorAction SilentlyContinue
        $totalFiles = $files.Count

        Write-Host "Found $totalFiles files to process`n" -ForegroundColor Yellow

        # Check PowerShell version for parallel support
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            Write-Host "Using PowerShell 7+ parallel processing" -ForegroundColor Green

            # Add index to files for progress tracking
            $filesWithIndex = $files | Select-Object *, @{Name='Index';Expression={$files.IndexOf($_) + 1}}

            # Use ForEach-Object -Parallel for PowerShell 7+
            $results = $filesWithIndex | ForEach-Object -Parallel {
                $file = $_
                $fileNum = $file.Index
                $total = $using:totalFiles

                try {
                    # Compute SHA-256 hash
                    $hash = Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction Stop

                    # Get file extension
                    $extension = $file.Extension
                    if ([string]::IsNullOrEmpty($extension)) {
                        $extension = "(none)"
                    }

                    # Create result object
                    $result = [PSCustomObject]@{
                        FileName = $file.Name
                        FileExtension = $extension
                        FilePath = $file.FullName
                        SHA256 = $hash.Hash
                        SizeBytes = $file.Length
                        SizeMB = [math]::Round($file.Length / 1MB, 2)
                        LastModified = $file.LastWriteTime
                        Status = "Success"
                        Error = ""
                    }

                    # Display progress for first 20 files
                    if ($fileNum -le 20) {
                        Write-Host "[$fileNum/$total] $($file.Name)" -ForegroundColor Green
                        Write-Host "  Hash: $($hash.Hash)" -ForegroundColor White
                        Write-Host "  Extension: $extension" -ForegroundColor Gray
                        Write-Host "  Path: $($file.FullName)" -ForegroundColor Gray
                        Write-Host ""
                    } elseif ($fileNum % 50 -eq 0) {
                        Write-Host "Progress: $fileNum/$total files processed..." -ForegroundColor Cyan
                    }

                    return $result

                } catch {
                    Write-Host "ERROR processing: $($file.FullName)" -ForegroundColor Red

                    # Return error result
                    return [PSCustomObject]@{
                        FileName = $file.Name
                        FileExtension = $file.Extension
                        FilePath = $file.FullName
                        SHA256 = "ERROR"
                        SizeBytes = $file.Length
                        SizeMB = [math]::Round($file.Length / 1MB, 2)
                        LastModified = $file.LastWriteTime
                        Status = "Error"
                        Error = $_.Exception.Message
                    }
                }
            } -ThrottleLimit $cpuThreads

        } else {
            Write-Host "Using PowerShell 5.1 single-threaded processing" -ForegroundColor Yellow
            Write-Host "(Upgrade to PowerShell 7+ for multi-threading support)`n" -ForegroundColor Yellow

            # Fallback to single-threaded for PowerShell 5.1
            $results = @()
            $fileCount = 0

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

                    # Get file extension
                    $extension = $file.Extension
                    if ([string]::IsNullOrEmpty($extension)) {
                        $extension = "(none)"
                    }

                    # Create result object
                    $result = [PSCustomObject]@{
                        FileName = $file.Name
                        FileExtension = $extension
                        FilePath = $file.FullName
                        SHA256 = $hash.Hash
                        SizeBytes = $file.Length
                        SizeMB = [math]::Round($file.Length / 1MB, 2)
                        LastModified = $file.LastWriteTime
                        Status = "Success"
                        Error = ""
                    }

                    $results += $result

                    # Display progress for first 20 files
                    if ($fileCount -le 20) {
                        Write-Host "[$fileCount/$totalFiles] $($file.Name)" -ForegroundColor Green
                        Write-Host "  Hash: $($hash.Hash)" -ForegroundColor White
                        Write-Host "  Extension: $extension" -ForegroundColor Gray
                        Write-Host "  Path: $($file.FullName)" -ForegroundColor Gray
                        Write-Host ""
                    }

                } catch {
                    Write-Host "ERROR processing: $($file.FullName)" -ForegroundColor Red
                    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
                }
            }

            Write-Progress -Activity "Computing file hashes" -Completed
        }

        # Filter out successful results
        $successfulResults = $results | Where-Object { $_.Status -eq "Success" }
        $errorCount = ($results | Where-Object { $_.Status -eq "Error" }).Count

        # Display summary
        Write-Host ("-" * 80) -ForegroundColor Gray
        Write-Host "`nHash computation completed!" -ForegroundColor Green
        Write-Host "Total files processed: $totalFiles" -ForegroundColor White
        Write-Host "Successful: $($successfulResults.Count)" -ForegroundColor Green
        Write-Host "Errors: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Green" })

        # Detect duplicates
        Write-Host "`nAnalyzing for duplicate files..." -ForegroundColor Cyan

        $hashGroups = $successfulResults | Group-Object -Property SHA256
        $duplicateGroups = $hashGroups | Where-Object { $_.Count -gt 1 }
        $duplicateCount = ($duplicateGroups | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum

        Write-Host "Found $($duplicateGroups.Count) groups of duplicate files" -ForegroundColor Yellow
        Write-Host "Total duplicate files: $duplicateCount" -ForegroundColor Yellow

        # Add duplicate detection fields
        $groupId = 0
        $finalResults = foreach ($result in $successfulResults) {
            $duplicateGroup = $duplicateGroups | Where-Object { $_.Name -eq $result.SHA256 }

            if ($duplicateGroup) {
                # This file is a duplicate
                $groupId++
                $result | Add-Member -MemberType NoteProperty -Name "DuplicatesExist" -Value $true -Force
                $result | Add-Member -MemberType NoteProperty -Name "DuplicateGroup" -Value $groupId -Force
            } else {
                # This file is unique
                $result | Add-Member -MemberType NoteProperty -Name "DuplicatesExist" -Value $false -Force
                $result | Add-Member -MemberType NoteProperty -Name "DuplicateGroup" -Value 0 -Force
            }

            # Remove Status and Error fields from final output
            $result | Select-Object FileName, FileExtension, FilePath, SHA256, SizeBytes, SizeMB, LastModified, DuplicatesExist, DuplicateGroup
        }

        return $finalResults

    } catch {
        Write-Host "ERROR: Failed to scan directory - $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Main script execution
try {
    Write-Host "`n=== Recursive File Hash Scanner (Multi-Threaded) ===" -ForegroundColor Cyan
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

            # Display duplicate file statistics
            $duplicates = $hashResults | Where-Object { $_.DuplicatesExist -eq $true }
            if ($duplicates.Count -gt 0) {
                Write-Host "`nDuplicate File Summary:" -ForegroundColor Yellow
                Write-Host "  Total duplicate files: $($duplicates.Count)" -ForegroundColor White
                Write-Host "  Duplicate groups: $(($duplicates | Select-Object -Unique DuplicateGroup).Count)" -ForegroundColor White
                Write-Host "  TIP: Filter CSV by 'DuplicatesExist=TRUE' to see all duplicates" -ForegroundColor Cyan
            }

            # Open the CSV file
            Write-Host "`nOpening CSV file..." -ForegroundColor Cyan
            Start-Process $exportPath

        } catch {
            Write-Host "ERROR: Failed to export results - $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # Display sample of results
    Write-Host "`n=== Sample Results (first 20 files) ===" -ForegroundColor Cyan
    $hashResults | Select-Object -First 20 | Format-Table -AutoSize FileName, FileExtension, SHA256, SizeMB, DuplicatesExist

    # Show duplicate examples if any exist
    $duplicateFiles = $hashResults | Where-Object { $_.DuplicatesExist -eq $true } | Select-Object -First 10
    if ($duplicateFiles.Count -gt 0) {
        Write-Host "`n=== Duplicate Files Detected (first 10) ===" -ForegroundColor Yellow
        $duplicateFiles | Format-Table -AutoSize FileName, FileExtension, DuplicateGroup, SHA256
    }

    Write-Host "`nScript completed successfully!" -ForegroundColor Green

} catch {
    Write-Host "`nFATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
