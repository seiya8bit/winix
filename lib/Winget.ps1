<#
.SYNOPSIS
    Winget package management module for winix
.DESCRIPTION
    Manages Winget packages with full sync support
#>

$ErrorActionPreference = 'Stop'

function Test-WingetInstalled {
    <#
    .SYNOPSIS
        Check if Winget is installed
    #>
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    return $null -ne $winget
}

function Assert-WingetInstalled {
    <#
    .SYNOPSIS
        Assert that Winget is installed, error if not
    #>
    if (-not (Test-WingetInstalled)) {
        Write-Error "Winget is not installed. Please install Windows Package Manager first."
        throw "Winget not installed"
    }
}

function Get-WingetInstalledApps {
    <#
    .SYNOPSIS
        Get list of installed Winget apps with versions
    .DESCRIPTION
        Uses winget export to get package IDs (version info not available in export format)
    #>
    try {
        # Use export command which provides locale-independent JSON output
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            winget export -o $tempFile --accept-source-agreements 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tempFile)) {
                return @()
            }

            $json = Get-Content -Path $tempFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $apps = @()

            if ($json.Sources) {
                foreach ($source in $json.Sources) {
                    if ($source.Packages) {
                        foreach ($pkg in $source.Packages) {
                            $apps += @{
                                name = $pkg.PackageIdentifier
                                version = $null  # Version not available in export format
                            }
                        }
                    }
                }
            }

            return $apps
        }
        finally {
            if (Test-Path $tempFile) {
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        return @()
    }
}

function Get-WingetPackageDiff {
    <#
    .SYNOPSIS
        Calculate differences between config and installed Winget packages
    .PARAMETER Config
        The normalized configuration
    .NOTES
        Unlike Scoop, Winget export doesn't include version info, so version comparison
        is not performed. Version-pinned packages are installed with specific version
        but cannot detect version mismatches afterward.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $diff = @{
        apps = @{
            toInstall = @()
            toRemove = @()
            toUpdate = @()  # Not used for winget due to version info limitation
        }
    }

    if (-not $Config.packages -or -not $Config.packages.winget -or -not $Config.packages.winget.apps) {
        return $diff
    }

    $installedApps = Get-WingetInstalledApps
    $installedAppIds = $installedApps | ForEach-Object { $_.name }

    foreach ($app in $Config.packages.winget.apps) {
        if ($app.name -notin $installedAppIds) {
            $diff.apps.toInstall += $app
        }
        # Note: Version comparison not possible since export doesn't include version
    }

    # Note: Winget uses "additive only" mode - packages not in config are NOT removed.
    # This differs from Scoop's full sync behavior because:
    # 1. Many system apps are managed by winget and shouldn't be removed
    # 2. Users typically have many winget packages they don't want to track declaratively

    return $diff
}

function Invoke-WingetPackageApply {
    <#
    .SYNOPSIS
        Apply Winget package changes
    .PARAMETER Config
        The normalized configuration
    .PARAMETER DryRun
        If set, only show what would be done
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [switch]$DryRun
    )

    if (-not $Config.packages -or -not $Config.packages.winget -or -not $Config.packages.winget.apps) {
        return @{ changes = 0 }
    }

    Assert-WingetInstalled

    $diff = Get-WingetPackageDiff -Config $Config
    $total = $diff.apps.toInstall.Count + $diff.apps.toRemove.Count + $diff.apps.toUpdate.Count
    $index = 0
    $changes = 0

    foreach ($app in $diff.apps.toInstall) {
        $index++
        $prefix = Format-ProgressPrefix -Index $index -Total $total
        if ($DryRun) {
            Write-Host "$prefix  + $($app.name)" -ForegroundColor Green -NoNewline
            Write-Host "             (would install)" -ForegroundColor DarkGray
        }
        else {
            Write-Host "$prefix  + $($app.name)" -ForegroundColor Green -NoNewline
            try {
                if ($app.version) {
                    winget install --id $app.name --version $app.version --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null
                }
                else {
                    winget install --id $app.name --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null
                }
                Write-Host "             done" -ForegroundColor DarkGray
            }
            catch {
                Write-Host "             failed" -ForegroundColor Red
                throw
            }
        }
        $changes++
    }

    foreach ($app in $diff.apps.toRemove) {
        $index++
        $prefix = Format-ProgressPrefix -Index $index -Total $total
        if ($DryRun) {
            Write-Host "$prefix  - $app" -ForegroundColor Red -NoNewline
            Write-Host "             (would remove)" -ForegroundColor DarkGray
        }
        else {
            Write-Host "$prefix  - $app" -ForegroundColor Red -NoNewline
            try {
                winget uninstall --id $app --silent 2>&1 | Out-Null
                Write-Host "             done" -ForegroundColor DarkGray
            }
            catch {
                Write-Host "             failed" -ForegroundColor Red
                throw
            }
        }
        $changes++
    }

    foreach ($app in $diff.apps.toUpdate) {
        $index++
        $prefix = Format-ProgressPrefix -Index $index -Total $total
        if ($DryRun) {
            Write-Host "$prefix  ~ $($app.name)" -ForegroundColor Yellow -NoNewline
            Write-Host "             (would update $($app.currentVersion) -> $($app.targetVersion))" -ForegroundColor DarkGray
        }
        else {
            Write-Host "$prefix  ~ $($app.name)" -ForegroundColor Yellow -NoNewline
            try {
                winget install --id $app.name --version $app.targetVersion --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null
                Write-Host "             done" -ForegroundColor DarkGray
            }
            catch {
                Write-Host "             failed" -ForegroundColor Red
                throw
            }
        }
        $changes++
    }

    return @{ changes = $changes }
}

function Show-WingetPackageStatus {
    <#
    .SYNOPSIS
        Show Winget package status differences
    .PARAMETER Config
        The normalized configuration
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    if (-not $Config.packages -or -not $Config.packages.winget -or -not $Config.packages.winget.apps) {
        return
    }

    $diff = Get-WingetPackageDiff -Config $Config

    $hasChanges = $diff.apps.toInstall.Count -gt 0 -or
                  $diff.apps.toRemove.Count -gt 0 -or
                  $diff.apps.toUpdate.Count -gt 0

    if (-not $hasChanges) {
        return
    }

    Write-SectionHeader -Title "Packages / Winget"

    foreach ($app in $diff.apps.toInstall) {
        Write-Host "  + $($app.name)" -ForegroundColor Green -NoNewline
        Write-Host "             (to install)" -ForegroundColor DarkGray
    }

    foreach ($app in $diff.apps.toRemove) {
        Write-Host "  - $app" -ForegroundColor Red -NoNewline
        Write-Host "             (to remove)" -ForegroundColor DarkGray
    }

    foreach ($app in $diff.apps.toUpdate) {
        Write-Host "  ~ $($app.name)" -ForegroundColor Yellow -NoNewline
        Write-Host "             ($($app.currentVersion) -> $($app.targetVersion))" -ForegroundColor DarkGray
    }
}

function Install-WingetPackage {
    <#
    .SYNOPSIS
        Install a Winget package and update winix.yaml
    .PARAMETER AppSpec
        The app specification (id or id@version)
    .PARAMETER Config
        The current configuration
    .PARAMETER ConfigPath
        Path to winix.yaml
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppSpec,
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    Assert-WingetInstalled

    $appId = $AppSpec
    $version = $null

    if ($AppSpec -match '^(.+)@(.+)$') {
        $appId = $Matches[1]
        $version = $Matches[2]
    }

    Write-Host "Installing: $AppSpec"
    if ($version) {
        winget install --id $appId --version $version --accept-source-agreements --accept-package-agreements
    }
    else {
        winget install --id $appId --accept-source-agreements --accept-package-agreements
    }

    if (-not $Config.packages.winget) {
        $Config.packages.winget = @{ apps = @() }
    }
    if (-not $Config.packages.winget.apps) {
        $Config.packages.winget.apps = @()
    }

    $appExists = $Config.packages.winget.apps | Where-Object { $_.name -eq $appId }
    if ($appExists) {
        $Config.packages.winget.apps = @($Config.packages.winget.apps | ForEach-Object {
            if ($_.name -eq $appId) {
                @{ name = $appId; version = $version }
            }
            else {
                $_
            }
        })
    }
    else {
        $Config.packages.winget.apps += @{ name = $appId; version = $version }
    }

    Update-WinixYaml -ConfigPath $ConfigPath -Packages $Config.packages

    Write-Host "Updated winix.yaml" -ForegroundColor Green
}

function Uninstall-WingetPackage {
    <#
    .SYNOPSIS
        Uninstall a Winget package and update winix.yaml
    .PARAMETER AppId
        The app ID to uninstall
    .PARAMETER Config
        The current configuration
    .PARAMETER ConfigPath
        Path to winix.yaml
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId,
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    Assert-WingetInstalled

    Write-Host "Uninstalling: $AppId"
    winget uninstall --id $AppId

    if ($Config.packages.winget -and $Config.packages.winget.apps) {
        $Config.packages.winget.apps = @($Config.packages.winget.apps | Where-Object { $_.name -ne $AppId })
    }

    Update-WinixYaml -ConfigPath $ConfigPath -Packages $Config.packages

    Write-Host "Updated winix.yaml" -ForegroundColor Green
}

function Update-WingetPackage {
    <#
    .SYNOPSIS
        Update Winget packages
    .PARAMETER AppId
        Optional app ID to update. If not specified, updates all.
    .PARAMETER Config
        The current configuration
    #>
    param(
        [string]$AppId,
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    Assert-WingetInstalled

    if ($AppId) {
        if ($Config.packages.winget -and $Config.packages.winget.apps) {
            $pinnedApp = $Config.packages.winget.apps | Where-Object { $_.name -eq $AppId -and $_.version }
            if ($pinnedApp) {
                Write-Warning "$AppId is pinned to version $($pinnedApp.version), skipping update"
                return
            }
        }
        Write-Host "Updating: $AppId"
        winget upgrade --id $AppId --accept-source-agreements --accept-package-agreements
    }
    else {
        $pinnedApps = @()
        if ($Config.packages.winget -and $Config.packages.winget.apps) {
            $pinnedApps = $Config.packages.winget.apps | Where-Object { $_.version }
        }
        $pinnedIds = $pinnedApps | ForEach-Object { $_.name }

        $installedApps = Get-WingetInstalledApps
        foreach ($app in $installedApps) {
            if ($app.name -in $pinnedIds) {
                Write-Warning "$($app.name) is pinned, skipping update"
                continue
            }
            winget upgrade --id $app.name --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        }
    }
}
