# Choco2Winget

Migrate your installed packages from Chocolatey to Windows Package Manager (Winget).

## What It Does

This script automates the migration process:

1. Retrieves all packages installed via Chocolatey
2. Searches for each package in the Winget repository
3. Prompts for confirmation before migrating (or auto-migrates with `-AcceptAll`)
4. Uninstalls from Chocolatey and reinstalls via Winget
5. Automatically rolls back if Winget installation fails
6. Generates a JSON report of all actions

## Prerequisites

- **Windows 10/11** (build 1809+)
- **PowerShell 5.1** or higher
- **Chocolatey** installed and in PATH
- **Winget** installed (comes with Windows 11, or install via [Microsoft Store](https://aka.ms/getwinget))
- **Administrator privileges** required

## Installation

```powershell
git clone https://github.com/osamaalassiry/choco2winget.git
cd choco2winget
```

## Usage

### Interactive Mode (Default)

Prompts for confirmation before each package migration:

```powershell
.\choco2winget.ps1
```

### Dry Run Mode

Preview what would be migrated without making changes:

```powershell
.\choco2winget.ps1 -DryRun
```

### Automatic Mode

Migrate all available packages without prompting:

```powershell
.\choco2winget.ps1 -AcceptAll
```

### Skip Specific Packages

Exclude packages from migration:

```powershell
.\choco2winget.ps1 -SkipPackages @('git', 'nodejs', 'python')
```

### Custom Report Location

Save the migration report to a specific directory:

```powershell
.\choco2winget.ps1 -ReportPath "C:\Logs"
```

### Combined Options

```powershell
.\choco2winget.ps1 -AcceptAll -SkipPackages @('git') -ReportPath "C:\Logs"
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-AcceptAll` | Switch | Skip confirmation prompts, migrate all available packages |
| `-DryRun` | Switch | Preview mode - no changes made |
| `-SkipPackages` | String[] | Array of package names to skip |
| `-ReportPath` | String | Directory for the JSON report (default: current directory) |

## Example Output

```
========================================
  Choco2Winget Migration Tool
========================================

Retrieving Chocolatey packages...
Found 15 Chocolatey packages.

[1/15] 7zip - FOUND (7zip.7zip)
    Migrate this package? (y/n/q to quit): y
    Uninstalling from Chocolatey...
    Installing via Winget...
    SUCCESS: Migrated to Winget

[2/15] vlc - FOUND (VideoLAN.VLC)
    Migrate this package? (y/n/q to quit): n
    Skipped by user.

[3/15] custompackage - NOT FOUND in Winget

...

========================================
  Migration Summary
========================================
  Total packages:    15
  Migrated:          8
  Skipped:           3
  Not in Winget:     4
  Failed:            0

Report saved: choco2winget_report_20240115_143052.json
```

## Migration Report

A JSON report is generated after each run:

```json
{
  "Timestamp": "2024-01-15 14:30:52",
  "DryRun": false,
  "Statistics": {
    "Total": 15,
    "Migrated": 8,
    "Skipped": 3,
    "NotFound": 4,
    "Failed": 0
  },
  "Packages": [
    {
      "Package": "7zip",
      "WingetId": "7zip.7zip",
      "Status": "Migrated",
      "Reason": "Success"
    },
    {
      "Package": "custompackage",
      "Status": "NotFound",
      "Reason": "Not available in Winget"
    }
  ]
}
```

## Safety Features

- **Prerequisite checks**: Verifies Chocolatey, Winget, and admin rights before starting
- **Automatic rollback**: If Winget installation fails, the package is reinstalled via Chocolatey
- **Dry-run mode**: Preview all changes before committing
- **Quit option**: Press `q` during interactive mode to stop migration
- **Detailed logging**: JSON report tracks all actions for review

## Why Migrate?

| Feature | Chocolatey | Winget |
|---------|------------|--------|
| Built into Windows | No | Yes (Win11) |
| Microsoft support | Community | Official |
| Package signing | Optional | Required |
| GUI integration | No | Yes (via Store) |

## Troubleshooting

### "This script requires Administrator privileges"

Right-click PowerShell and select "Run as Administrator", then run the script again.

### "Missing required package managers: Chocolatey"

Install Chocolatey first:
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

### "Missing required package managers: Winget"

Install Winget from the [Microsoft Store](https://aka.ms/getwinget) or via the [App Installer package](https://github.com/microsoft/winget-cli/releases).

### Package not found in Winget

Not all Chocolatey packages exist in Winget. Check manually:
```powershell
winget search "package-name"
```

### Rollback failed

If both uninstall and rollback fail, manually reinstall:
```powershell
choco install package-name -y
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
