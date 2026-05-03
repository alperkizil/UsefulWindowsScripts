# UsefulWindowsScripts
A collection of useful PowerShell scripts for Windows system administration and file management.

## Scripts

### VTScanner

A right-click VirusTotal scanner for Windows 10. Hashes any file with SHA-256,
looks the hash up on VirusTotal, and shows the detection ratio in a small
results window with a toast notification. Also includes a Task-Manager-style
process picker so you can scan the executable behind any running process.

See [`VTScanner/README.md`](VTScanner/README.md) for install steps, usage, and
caveats.

### ReportFileSignatures.ps1

A high-performance PowerShell script that recursively scans directories, calculates SHA-256 file signatures, detects duplicates, and generates comprehensive CSV reports.

#### Features

- **Modern Folder Browser**: GUI folder selection dialog defaulting to Documents folder
- **Recursive Scanning**: Scans all files in selected directory and all subdirectories
- **SHA-256 Hashing**: Calculates cryptographic hash for each file
- **Duplicate Detection**: Automatically identifies duplicate files and groups them
- **Multi-threaded Processing**: Utilizes all CPU threads for maximum performance
- **Real-time Progress**: Live progress bar showing file count, percentage, and elapsed time
- **Error Handling**: Gracefully handles inaccessible files and provides detailed error summary
- **Auto-export**: Generates timestamped CSV report and opens it automatically
- **Cross-version Compatible**: Works with both PowerShell 5.1 and PowerShell 7+

#### Requirements

- Windows 10/11
- PowerShell 5.1 or higher
- .NET Framework (for PowerShell 5.1) or PowerShell 7+

#### Usage

```powershell
.\ReportFileSignatures.ps1
```

1. Run the script
2. Select a folder using the browser dialog
3. Wait for processing to complete
4. Review the auto-opened CSV report

#### Output Format

The script generates a CSV file with the following columns:

| Column | Description | Type |
|--------|-------------|------|
| SHA256 | Cryptographic hash of file contents | String |
| FileName | Name of the file with extension | String |
| Directory | Full directory path | String |
| FileExtension | File extension (e.g., .txt, .jpg) | String |
| SizeKB | File size in kilobytes | Decimal |
| SizeMB | File size in megabytes | Decimal |
| SizeGB | File size in gigabytes | Decimal |
| LastModified | Last modification timestamp | DateTime |
| IsDuplicate | Whether file is a duplicate | Boolean |
| DuplicateGroupID | Numeric identifier for duplicate groups | Integer |

#### Performance

- **Multi-threading**: Automatically detects and uses all available CPU threads
  - Example: 12-core/24-thread CPU (Ryzen 5900X) = 24 parallel workers
- **Optimized I/O**: Concurrent file processing with thread-safe collections
- **Progress Tracking**: Real-time synchronized progress updates

#### Example Output

```
=== File Signature Report Generator ===
PowerShell Version: 7

Selected folder: C:\Users\Username\Documents
Found 1,523 files to process.

CPU Thread Count: 24
Starting multi-threaded processing...
Using PowerShell 7+ parallel processing

[Progress: 1523/1523 (100%) | Elapsed: 00:02:34] Processing: document.pdf

=== SUMMARY ===
Total files scanned: 1523
Successfully processed: 1520
Files with errors (skipped): 3
Duplicate files found: 45 (in 18 groups)
Total time elapsed: 00:02:34
Report saved to: C:\Users\Username\Documents\FileSignatureReport_20251220_143022.csv
```

#### Error Handling

Files that cannot be accessed (locked, permission denied, corrupted) are:
- Skipped automatically
- Logged with error details
- Summarized at completion
- Listed individually in the final report

#### Use Cases

- **Duplicate File Detection**: Find and remove duplicate files to free up disk space
- **File Integrity Verification**: Verify file integrity across backups
- **Data Deduplication**: Identify redundant data in large directories
- **Forensic Analysis**: Document file signatures for security audits
- **Archive Management**: Catalog file collections with metadata
- **Compliance**: Generate file inventories for regulatory requirements
