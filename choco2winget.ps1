<#
.SYNOPSIS
    Migrates packages from Chocolatey to Windows Package Manager (Winget).

.DESCRIPTION
    This script automates the migration of installed Chocolatey packages to Winget.
    For each package, it checks availability in Winget, prompts for confirmation,
    then uninstalls from Chocolatey and reinstalls via Winget.

    Features:
    - Prerequisite validation (choco, winget, admin rights)
    - Dry-run mode for previewing changes
    - Automatic mode for unattended migration
    - Rollback on failed installations
    - Migration report generation

.PARAMETER AcceptAll
    Automatically migrate all available packages without prompting.

.PARAMETER DryRun
    Preview what would be migrated without making any changes.

.PARAMETER SkipPackages
    Array of package names to skip during migration.

.PARAMETER ReportPath
    Path to save the migration report. Defaults to current directory.

.EXAMPLE
    .\choco2winget.ps1
    Interactive mode - prompts for each package.

.EXAMPLE
    .\choco2winget.ps1 -DryRun
    Preview mode - shows what would be migrated.

.EXAMPLE
    .\choco2winget.ps1 -AcceptAll
    Automatic mode - migrates all available packages.

.EXAMPLE
    .\choco2winget.ps1 -SkipPackages @('git', 'nodejs')
    Skip specific packages during migration.

.NOTES
    Author: Osama Al Assiry
    Requires: PowerShell 5.1+, Chocolatey, Winget, Administrator privileges
#>

#Requires -Version 5.1

param(
    [switch]$AcceptAll,
    [switch]$DryRun,
    [string[]]$SkipPackages = @(),
    [string]$ReportPath = "."
)

# Check for administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "ERROR: This script requires Administrator privileges." -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
    exit 1
}

# Verify prerequisites
function Test-Prerequisites {
    $missing = @()

    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        $missing += "Chocolatey"
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        $missing += "Winget"
    }

    if ($missing.Count -gt 0) {
        Write-Host "ERROR: Missing required package managers: $($missing -join ', ')" -ForegroundColor Red
        exit 1
    }
}

# Extract package name from choco list output
function Get-PackageName {
    param([string]$PackageEntry)

    # Remove version number (handles both "package 1.2.3" and "package v1.2.3")
    $name = $PackageEntry -replace '\s+v?\d+[\d\.\-a-zA-Z]*$'
    return $name.Trim()
}

# Search for package in Winget and return match info
function Find-WingetPackage {
    param([string]$PackageName)

    $result = @{
        Found = $false
        Id = $null
        Name = $null
        Version = $null
    }

    try {
        $searchOutput = winget search --name $PackageName --accept-source-agreements 2>$null

        # Parse winget output - look for exact or close match
        foreach ($line in $searchOutput) {
            # Skip header lines
            if ($line -match "^Name\s+" -or $line -match "^-+") { continue }
            if ($line -match "^\s*$") { continue }

            # Check if package name appears in the line (case-insensitive)
            if ($line -match "(?i)$([regex]::Escape($PackageName))") {
                # Parse the line - winget output is space-separated columns
                $parts = $line -split '\s{2,}'
                if ($parts.Count -ge 2) {
                    $result.Found = $true
                    $result.Name = $parts[0].Trim()
                    $result.Id = if ($parts.Count -ge 2) { $parts[1].Trim() } else { $null }
                    $result.Version = if ($parts.Count -ge 3) { $parts[2].Trim() } else { $null }
                    break
                }
            }
        }
    } catch {
        Write-Host "  Warning: Error searching Winget: $_" -ForegroundColor Yellow
    }

    return $result
}

# Main script execution
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Choco2Winget Migration Tool" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN MODE] No changes will be made." -ForegroundColor Yellow
    Write-Host ""
}

# Verify prerequisites
Test-Prerequisites

# Get installed Chocolatey packages
Write-Host "Retrieving Chocolatey packages..." -ForegroundColor Cyan
$tempFile = Join-Path $env:TEMP "choco2winget_$(Get-Random).txt"

try {
    choco list --localonly > $tempFile 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to retrieve Chocolatey package list." -ForegroundColor Red
        exit 1
    }

    $chocoPackages = Get-Content -Path $tempFile | Where-Object {
        # Filter out summary lines and empty lines
        $_ -and $_ -notmatch "^\d+ packages installed" -and $_ -notmatch "^Chocolatey"
    }
} finally {
    if (Test-Path $tempFile) {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

$packageCount = @($chocoPackages).Count
Write-Host "Found $packageCount Chocolatey packages." -ForegroundColor Green
Write-Host ""

# Initialize tracking
$stats = @{
    Total = $packageCount
    Migrated = 0
    Skipped = 0
    NotFound = 0
    Failed = 0
}
$migrationLog = @()
$i = 0

foreach ($package in $chocoPackages) {
    $i++
    $packageName = Get-PackageName -PackageEntry $package

    if ([string]::IsNullOrWhiteSpace($packageName)) { continue }

    # Progress indicator
    $percent = [math]::Round(($i / $packageCount) * 100)
    Write-Host "[$i/$packageCount] " -NoNewline -ForegroundColor DarkGray
    Write-Host "$packageName" -NoNewline -ForegroundColor White

    # Check if package should be skipped
    if ($packageName -in $SkipPackages) {
        Write-Host " - SKIPPED (in skip list)" -ForegroundColor Yellow
        $stats.Skipped++
        $migrationLog += [PSCustomObject]@{
            Package = $packageName
            Status = "Skipped"
            Reason = "In skip list"
        }
        continue
    }

    # Search in Winget
    Write-Host " - searching..." -NoNewline -ForegroundColor DarkGray
    $wingetResult = Find-WingetPackage -PackageName $packageName

    if (-not $wingetResult.Found) {
        Write-Host "`r[$i/$packageCount] $packageName - " -NoNewline
        Write-Host "NOT FOUND in Winget" -ForegroundColor Yellow
        $stats.NotFound++
        $migrationLog += [PSCustomObject]@{
            Package = $packageName
            Status = "NotFound"
            Reason = "Not available in Winget"
        }
        continue
    }

    # Found in Winget
    Write-Host "`r[$i/$packageCount] $packageName - " -NoNewline
    Write-Host "FOUND" -NoNewline -ForegroundColor Green
    if ($wingetResult.Id) {
        Write-Host " ($($wingetResult.Id))" -ForegroundColor DarkGray
    } else {
        Write-Host ""
    }

    # Get confirmation
    $shouldMigrate = $false
    if ($AcceptAll) {
        $shouldMigrate = $true
    } elseif (-not $DryRun) {
        $response = Read-Host "    Migrate this package? (y/n/q to quit)"
        $response = $response.ToLower().Trim()

        if ($response -eq 'q') {
            Write-Host "`nMigration cancelled by user." -ForegroundColor Yellow
            break
        }
        $shouldMigrate = $response -in @('y', 'yes')
    }

    if ($DryRun) {
        Write-Host "    [DRY RUN] Would migrate: $packageName -> $($wingetResult.Id)" -ForegroundColor Gray
        $migrationLog += [PSCustomObject]@{
            Package = $packageName
            WingetId = $wingetResult.Id
            Status = "WouldMigrate"
            Reason = "Dry run"
        }
        continue
    }

    if (-not $shouldMigrate) {
        Write-Host "    Skipped by user." -ForegroundColor DarkGray
        $stats.Skipped++
        $migrationLog += [PSCustomObject]@{
            Package = $packageName
            Status = "Skipped"
            Reason = "User declined"
        }
        continue
    }

    # Perform migration
    Write-Host "    Uninstalling from Chocolatey..." -ForegroundColor Cyan
    $uninstallSuccess = $false

    try {
        choco uninstall $packageName -y --force 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $uninstallSuccess = $true
        }
    } catch {
        Write-Host "    ERROR: Chocolatey uninstall failed: $_" -ForegroundColor Red
    }

    if (-not $uninstallSuccess) {
        Write-Host "    ERROR: Failed to uninstall from Chocolatey. Skipping." -ForegroundColor Red
        $stats.Failed++
        $migrationLog += [PSCustomObject]@{
            Package = $packageName
            Status = "Failed"
            Reason = "Chocolatey uninstall failed"
        }
        continue
    }

    Write-Host "    Installing via Winget..." -ForegroundColor Cyan
    $installSuccess = $false
    $installTarget = if ($wingetResult.Id) { $wingetResult.Id } else { $packageName }

    try {
        winget install --id $installTarget --accept-package-agreements --accept-source-agreements -h 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $installSuccess = $true
        }
    } catch {
        Write-Host "    ERROR: Winget install failed: $_" -ForegroundColor Red
    }

    if ($installSuccess) {
        Write-Host "    SUCCESS: Migrated to Winget" -ForegroundColor Green
        $stats.Migrated++
        $migrationLog += [PSCustomObject]@{
            Package = $packageName
            WingetId = $installTarget
            Status = "Migrated"
            Reason = "Success"
        }
    } else {
        # Rollback - reinstall via Chocolatey
        Write-Host "    WARNING: Winget install failed. Rolling back..." -ForegroundColor Yellow
        choco install $packageName -y 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Host "    Rollback successful - package restored via Chocolatey." -ForegroundColor Yellow
        } else {
            Write-Host "    CRITICAL: Rollback failed! Package may need manual reinstall." -ForegroundColor Red
        }

        $stats.Failed++
        $migrationLog += [PSCustomObject]@{
            Package = $packageName
            Status = "Failed"
            Reason = "Winget install failed, rolled back"
        }
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Migration Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Total packages:    $($stats.Total)" -ForegroundColor White
Write-Host "  Migrated:          $($stats.Migrated)" -ForegroundColor Green
Write-Host "  Skipped:           $($stats.Skipped)" -ForegroundColor Yellow
Write-Host "  Not in Winget:     $($stats.NotFound)" -ForegroundColor Yellow
Write-Host "  Failed:            $($stats.Failed)" -ForegroundColor $(if ($stats.Failed -gt 0) { 'Red' } else { 'White' })
Write-Host ""

# Save report
$reportFile = Join-Path $ReportPath "choco2winget_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$report = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    DryRun = $DryRun.IsPresent
    Statistics = $stats
    Packages = $migrationLog
}

try {
    $report | ConvertTo-Json -Depth 3 | Set-Content -Path $reportFile
    Write-Host "Report saved: $reportFile" -ForegroundColor DarkGray
} catch {
    Write-Host "Warning: Could not save report: $_" -ForegroundColor Yellow
}

Write-Host ""
