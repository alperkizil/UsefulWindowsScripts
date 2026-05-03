# VTScanner

A small Windows 10 utility that lets you look up a file on
[VirusTotal](https://www.virustotal.com/) by SHA-256 and see whether anything
flags it — directly from the right-click menu, or by picking a running process
from a Task-Manager-style list.

It's deliberately *not* a real-time AV: each scan is user-initiated, results
are cached, and there is no automatic quarantine.

## Features

- **Right-click any file → "Scan with VirusTotal"** — works on any file type.
- **Start Menu → "VTScanner — Scan Running Process"** — picks a running
  process from a sortable, filterable list and scans its executable.
- Native Windows toast + a results window showing
  `X / 72 detections`, color-coded green / yellow / red, with a button that
  jumps to the full VirusTotal report.
- For files VirusTotal hasn't seen, prompts to upload (≤ 32 MB) or shows a
  "too large" message.
- Per-user cache (24 h for clean files, 1 h for flagged) so repeat scans are
  near-instant and don't burn API quota.
- Per-user log of every scan at `%LOCALAPPDATA%\VTScanner\scan.log`.

## Requirements

- Windows 10 (1809 or newer recommended for native toasts).
- Windows PowerShell 5.1 (preinstalled) or PowerShell 7+.
- A free VirusTotal API key — get one at
  <https://www.virustotal.com/gui/my-apikey>.
- Local administrator rights for install/uninstall.

## Install

Two ways — pick one.

### Option A — One-click `VTScanner-Setup.exe` (recommended)

A single self-contained installer .exe that bundles every VTScanner script
inside it. Double-click → approve the UAC prompt → enter your VirusTotal API
key. Done.

The .exe is **not** committed to this repo (binary artifacts don't belong in
source). Build it once on any Windows box with:

```powershell
cd <repo>\VTScanner
.\Build-VTScannerInstaller.ps1
```

This produces `VTScanner-Setup.exe` (next to the repo). Distribute that single
file. It uses Windows' built-in IExpress packager — no third-party tooling.

### Option B — Run the PowerShell installer directly

From an **elevated** PowerShell prompt:

```powershell
cd <repo>\VTScanner
.\Install-VTScanner.ps1
```

### Either way

Paste your VirusTotal API key when prompted. Click **Test** to verify it,
then **Save**.

The installer:

- copies the scripts to `%ProgramFiles%\VTScanner\`,
- generates `VTScanner.ico` (multi-resolution shield + magnifier),
- DPAPI-encrypts the API key (`LocalMachine` scope) into
  `%ProgramData%\VTScanner\config.json`,
- registers the right-click entry under
  `HKLM\SOFTWARE\Classes\*\shell\VTScan`,
- creates a Start Menu shortcut **VTScanner — Scan Running Process** that
  asks for elevation when launched.

## Usage

### Right-click a file

In Explorer, right-click any file → **Scan with VirusTotal**. After a moment
you'll get a toast and a results window:

- **Green** `0 / N`: no engine flagged the file.
- **Yellow** `1–3 / N`: a few engines raised warnings — review on VT before
  trusting.
- **Red** `≥ 4 / N`: many engines call it malicious or suspicious.
- **Unknown to VirusTotal**: VT has no record of this hash. If the file is
  ≤ 32 MB you'll see an **Upload to VirusTotal** button; for larger files VT
  cannot accept the submission via the public API.

### Pick a running process

Open **Start → VTScanner → VTScanner — Scan Running Process**. Approve the UAC
prompt (elevation is required to read paths of elevated processes). Filter the
list, select one process, click **Scan Selected**.

Protected and kernel processes whose paths Windows refuses to expose appear
greyed-out and can't be selected.

## File and registry layout

| Path | Purpose |
|---|---|
| `%ProgramFiles%\VTScanner\` | Installed scripts and the generated icon |
| `%ProgramData%\VTScanner\config.json` | DPAPI-encrypted API key (LocalMachine scope) |
| `%LOCALAPPDATA%\VTScanner\cache.json` | Per-user lookup cache |
| `%LOCALAPPDATA%\VTScanner\scan.log` | Per-user scan log |
| `HKLM\SOFTWARE\Classes\*\shell\VTScan` | Right-click context menu entry |
| `HKCU\Software\Classes\AppUserModelId\Anthropic.VTScanner` | Toast app id (registered lazily on first toast) |
| `%ProgramData%\Microsoft\Windows\Start Menu\Programs\VTScanner\` | Start Menu shortcut for the process picker |

## Uninstall

From an elevated prompt:

```powershell
& "$env:ProgramFiles\VTScanner\Uninstall-VTScanner.ps1"
```

Add `-Purge` to also delete the per-user cache and log under
`%LOCALAPPDATA%\VTScanner\`.

## Caveats

- **Privacy on upload:** uploading a file to VirusTotal makes it accessible to
  VT and its partners. Don't upload anything sensitive. The scanner only
  uploads when you explicitly click **Upload to VirusTotal**.
- **API key storage:** DPAPI `LocalMachine` scope means any user/process on
  this machine can decrypt the key. Acceptable for a per-machine install on a
  single-user box; not appropriate for shared/multi-tenant systems.
- **Execution policy:** the registry command launches PowerShell with
  `-ExecutionPolicy Bypass` per invocation. The installed scripts are not
  signed.
- **Free API limits:** 4 requests/minute, 500/day. The cache absorbs most
  repeat scans, but heavy use of the process picker can still hit the limit.
- **Out of scope:** real-time/background monitoring, automatic quarantine,
  bulk auto-scan of all running processes, multi-select.

## Files

- `VTScanner.ps1` — scan/cache/UI core (called by context menu, dot-sourced by picker).
- `VTScanner-ProcessPicker.ps1` — running-process picker GUI.
- `Install-VTScanner.ps1` — one-time installer (admin).
- `Uninstall-VTScanner.ps1` — cleanup (admin).
- `New-VTScannerIcon.ps1` — generates `VTScanner.ico` via GDI+.
- `Build-VTScannerInstaller.ps1` — packages the above into `VTScanner-Setup.exe` via IExpress.
