<#
.SYNOPSIS
    Steam apps installation task for winix
.DESCRIPTION
    Manages Steam app installations via steam:// protocol
#>

$ErrorActionPreference = 'Stop'

function global:Get-TaskInfo {
    <#
    .SYNOPSIS
        Returns task information
    #>
    return @{
        Name        = "Steam Apps"
        Description = "Install Steam apps via steam:// protocol"
        Version     = "1.0.0"
    }
}

function global:_GetSteamPath {
    <#
    .SYNOPSIS
        Get Steam installation path
    #>
    $paths = @(
        "${env:ProgramFiles(x86)}\Steam",
        "$env:ProgramFiles\Steam",
        "$env:USERPROFILE\scoop\apps\steam\current"
    )

    foreach ($path in $paths) {
        if (Test-Path $path) {
            return $path
        }
    }

    # Try registry
    try {
        $regPath = Get-ItemPropertyValue -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue
        if ($regPath -and (Test-Path $regPath)) {
            return $regPath
        }
    }
    catch {}

    return $null
}

function global:_GetSteamLibraryFolders {
    <#
    .SYNOPSIS
        Get all Steam library folders
    #>
    $steamPath = _GetSteamPath
    if (-not $steamPath) {
        return @()
    }

    $libraryFoldersPath = Join-Path $steamPath "steamapps\libraryfolders.vdf"
    if (-not (Test-Path $libraryFoldersPath)) {
        return @(Join-Path $steamPath "steamapps")
    }

    $libraries = @()
    $content = Get-Content -Path $libraryFoldersPath -Raw

    # Parse VDF format to extract paths
    $matches = [regex]::Matches($content, '"path"\s+"([^"]+)"')
    foreach ($match in $matches) {
        $libPath = $match.Groups[1].Value -replace '\\\\', '\'
        $steamappsPath = Join-Path $libPath "steamapps"
        if (Test-Path $steamappsPath) {
            $libraries += $steamappsPath
        }
    }

    if ($libraries.Count -eq 0) {
        $libraries += Join-Path $steamPath "steamapps"
    }

    return $libraries
}

function global:_GetInstalledSteamApps {
    <#
    .SYNOPSIS
        Get list of installed Steam app IDs
    #>
    $libraries = _GetSteamLibraryFolders
    $installedApps = @()

    foreach ($library in $libraries) {
        $manifests = Get-ChildItem -Path $library -Filter "appmanifest_*.acf" -ErrorAction SilentlyContinue
        foreach ($manifest in $manifests) {
            if ($manifest.Name -match 'appmanifest_(\d+)\.acf') {
                $appId = $Matches[1]
                if ($appId -notin $installedApps) {
                    $installedApps += $appId
                }
            }
        }
    }

    return $installedApps
}

function global:_IsSteamRunning {
    <#
    .SYNOPSIS
        Check if Steam process is running
    #>
    $steamProcess = Get-Process -Name "steam" -ErrorAction SilentlyContinue
    return $null -ne $steamProcess
}

function global:_EnsureSteamRunning {
    <#
    .SYNOPSIS
        Ensure Steam is running and user is logged in
    .RETURNS
        $true if Steam is ready, $false if user skipped
    #>
    if (_IsSteamRunning) {
        return $true
    }

    Write-Host ""
    Write-Host "  Steam is not running." -ForegroundColor Yellow
    Write-Host "  Please start Steam and login to your account." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Press Enter after logging in (or type 'skip' to skip Steam tasks): " -ForegroundColor Yellow -NoNewline
    $response = Read-Host

    if ($response -eq "skip") {
        return $false
    }

    # Check again
    if (-not (_IsSteamRunning)) {
        Write-Host "  Steam still not detected. Skipping Steam tasks." -ForegroundColor DarkGray
        return $false
    }

    return $true
}

function global:_GetAppName {
    <#
    .SYNOPSIS
        Get app name from manifest or return app ID
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId
    )

    $libraries = _GetSteamLibraryFolders
    foreach ($library in $libraries) {
        $manifestPath = Join-Path $library "appmanifest_$AppId.acf"
        if (Test-Path $manifestPath) {
            $content = Get-Content -Path $manifestPath -Raw
            if ($content -match '"name"\s+"([^"]+)"') {
                return $Matches[1]
            }
        }
    }

    return "App $AppId"
}

function global:Get-TaskStatus {
    <#
    .SYNOPSIS
        Get current installation status
    .PARAMETER Config
        Task configuration from winix.yaml
    .PARAMETER TaskState
        Task state from winix state.json
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [Parameter(Mandatory = $false)]
        [hashtable]$TaskState = @{ items = @() }
    )

    $status = @{
        ToInstall = @()
        ToRemove  = @()
        UpToDate  = @()
    }

    $configApps = @()
    if ($Config.apps) {
        $configApps = @($Config.apps | ForEach-Object { $_.ToString() })
    }
    $stateItems = @()
    if ($TaskState.items) {
        $stateItems = @($TaskState.items)
    }

    $steamPath = _GetSteamPath
    if (-not $steamPath) {
        Write-Warning "Steam is not installed"
        foreach ($appId in $stateItems) {
            if ($appId -notin $configApps) {
                $status.ToRemove += "Steam not installed (drop from state): $appId"
            }
        }
        return $status
    }

    $installedApps = _GetInstalledSteamApps

    # Check apps in config
    foreach ($appId in $configApps) {
        $appName = if ($Config.names -and $Config.names[$appId]) {
            $Config.names[$appId]
        }
        else {
            _GetAppName -AppId $appId
        }

        $displayName = "$appName ($appId)"

        if ($appId -in $installedApps) {
            $status.UpToDate += $displayName
        }
        else {
            $status.ToInstall += $displayName
        }
    }

    # Check apps in state but not in config (ToRemove)
    foreach ($appId in $stateItems) {
        if ($appId -notin $configApps) {
            $appName = _GetAppName -AppId $appId
            $displayName = "$appName ($appId)"
            $status.ToRemove += $displayName
        }
    }

    return $status
}

function global:Invoke-TaskApply {
    <#
    .SYNOPSIS
        Install Steam apps
    .PARAMETER Config
        Task configuration from winix.yaml
    .PARAMETER TaskState
        Task state from winix state.json
    .PARAMETER DryRun
        If set, only show what would be done
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [Parameter(Mandatory = $false)]
        [hashtable]$TaskState = @{ items = @() },
        [switch]$DryRun
    )

    $result = @{
        installed = @()
        removed = @()
    }

    $steamPath = _GetSteamPath
    if (-not $steamPath) {
        # Drop stale state entries when Steam is not installed.
        $configApps = @()
        if ($Config.apps) {
            $configApps = @($Config.apps | ForEach-Object { $_.ToString() })
        }
        $stateItems = @()
        if ($TaskState.items) {
            $stateItems = @($TaskState.items)
        }
        foreach ($appId in $stateItems) {
            if ($appId -notin $configApps) {
                $result.removed += $appId
            }
        }
        Write-Warning "Steam is not installed; cleaned up task state for removed apps."
        return $result
    }

    # Ensure Steam is running before attempting install/uninstall
    if (-not (_EnsureSteamRunning)) {
        Write-Host "  Skipping Steam tasks." -ForegroundColor DarkGray
        return $result
    }

    $installedApps = _GetInstalledSteamApps
    $configApps = @()
    if ($Config.apps) {
        $configApps = @($Config.apps | ForEach-Object { $_.ToString() })
    }
    $stateItems = @()
    if ($TaskState.items) {
        $stateItems = @($TaskState.items)
    }

    # Install apps in config
    $appsToInstall = @()
    foreach ($appId in $configApps) {
        if ($appId -in $installedApps) {
            # Already installed, just track in state
            $result.installed += $appId
        }
        else {
            $appsToInstall += $appId
        }
    }

    $hasNewInstalls = $false
    if ($appsToInstall.Count -gt 0 -and -not $DryRun) {
        foreach ($appId in $appsToInstall) {
            Write-Host "    Opening Steam install dialog..." -ForegroundColor DarkGray
            Start-Process "steam://install/$appId"
            Start-Sleep -Seconds 2
        }
        $hasNewInstalls = $true

        Write-Host ""
        Write-Host "  Waiting for installation to complete..." -ForegroundColor Yellow
        Write-Host "  Press Enter after completing or canceling the install dialogs." -ForegroundColor Yellow
        Read-Host | Out-Null

        # Re-check which apps are actually installed
        $currentInstalledApps = _GetInstalledSteamApps
        foreach ($appId in $appsToInstall) {
            if ($appId -in $currentInstalledApps) {
                # Actually installed
                $result.installed += $appId
                Write-Host "    Installed: $appId" -ForegroundColor Green
            }
            else {
                # Not installed (user canceled)
                Write-Host "    Skipped (not installed): $appId" -ForegroundColor DarkGray
            }
        }
    }

    # Handle apps removed from config (uninstall)
    $appsToUninstall = @()
    foreach ($appId in $stateItems) {
        if ($appId -notin $configApps) {
            $appsToUninstall += $appId
        }
    }

    $hasUninstalls = $false
    if ($appsToUninstall.Count -gt 0 -and -not $DryRun) {
        foreach ($appId in $appsToUninstall) {
            Write-Host "    Opening Steam uninstall dialog..." -ForegroundColor DarkGray
            Start-Process "steam://uninstall/$appId"
            Start-Sleep -Seconds 2
        }
        $hasUninstalls = $true

        Write-Host ""
        Write-Host "  Waiting for uninstallation to complete..." -ForegroundColor Yellow
        Write-Host "  Press Enter after completing or canceling the uninstall dialogs." -ForegroundColor Yellow
        Read-Host | Out-Null

        # Re-check which apps are actually uninstalled
        $currentInstalledApps = _GetInstalledSteamApps
        foreach ($appId in $appsToUninstall) {
            if ($appId -notin $currentInstalledApps) {
                # Actually uninstalled
                $result.removed += $appId
                Write-Host "    Uninstalled: $appId" -ForegroundColor Green
            }
            else {
                # Still installed (user canceled)
                Write-Host "    Skipped (still installed): $appId" -ForegroundColor DarkGray
            }
        }
    }

    return $result
}

function global:Invoke-TaskCleanup {
    <#
    .SYNOPSIS
        Clean up task-specific helper functions
    #>
    Remove-Item -Path "Function:\_GetSteamPath" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetSteamLibraryFolders" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetInstalledSteamApps" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_IsSteamRunning" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_EnsureSteamRunning" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetAppName" -ErrorAction SilentlyContinue
}
