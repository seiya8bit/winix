<#
.SYNOPSIS
    Scoop package management module for winix
.DESCRIPTION
    Manages Scoop packages and buckets with full sync support
#>

$ErrorActionPreference = 'Stop'

function Test-ScoopInstalled {
    <#
    .SYNOPSIS
        Check if Scoop is installed
    #>
    $scoop = Get-Command scoop -ErrorAction SilentlyContinue
    return $null -ne $scoop
}

function _EnsureGsudo {
    <#
    .SYNOPSIS
        Ensure gsudo is installed, install if not
    #>
    if (-not (Test-GsudoInstalled)) {
        Write-Host "             installing gsudo..." -ForegroundColor Yellow -NoNewline
        scoop install gsudo 2>&1 | Out-Null
        if (-not (Test-GsudoInstalled)) {
            throw "Failed to install gsudo"
        }
    }
}

function _InvokeScoopInstall {
    <#
    .SYNOPSIS
        Install a Scoop package, using gsudo if admin rights are required
    .PARAMETER AppSpec
        The app specification (app or app@version)
    .PARAMETER Silent
        If set, suppress output to Out-Null
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppSpec,
        [switch]$Silent
    )

    # Extract app name from spec (remove version if present)
    $appName = $AppSpec
    if ($AppSpec -match '^(.+)@(.+)$') {
        $appName = $Matches[1]
    }

    # Capture all output streams including Write-Host (stream 6)
    if ($Silent) {
        $output = & { scoop install $AppSpec } *>&1
    }
    else {
        $output = & { scoop install $AppSpec } *>&1 | Tee-Object -Variable output
    }
    $outputString = $output -join "`n"
    $exitCode = $LASTEXITCODE

    # Check if installation requires admin rights
    $needsAdmin = $outputString -match "requires admin rights"

    # Also check if installation actually succeeded by verifying the app is installed
    if (-not $needsAdmin) {
        $installedApps = Get-InstalledApps
        $isInstalled = $installedApps | Where-Object { $_.name -eq $appName }
        if (-not $isInstalled -and ($exitCode -ne 0 -or $outputString -match "error|failed")) {
            # Installation failed, check if it might be an admin rights issue
            $needsAdmin = $true
        }
    }

    if ($needsAdmin) {
        _EnsureGsudo
        Write-Host " (elevating)" -ForegroundColor Yellow -NoNewline
        if ($Silent) {
            gsudo scoop install $AppSpec *>&1 | Out-Null
        }
        else {
            gsudo scoop install $AppSpec
        }
        # Verify installation after elevation
        $installedApps = Get-InstalledApps
        $isInstalled = $installedApps | Where-Object { $_.name -eq $appName }
        if (-not $isInstalled) {
            throw "scoop install failed even with elevation: $appName"
        }
    }
    elseif ($exitCode -ne 0 -and $outputString -match "error|failed") {
        throw "scoop install failed: $outputString"
    }
}

function Assert-ScoopInstalled {
    <#
    .SYNOPSIS
        Assert that Scoop is installed, error if not
    #>
    if (-not (Test-ScoopInstalled)) {
        Write-Error "Scoop is not installed. Please run bootstrap.ps1 first."
        throw "Scoop not installed"
    }
}

function _GetScoopExport {
    <#
    .SYNOPSIS
        Get scoop export data as parsed object
    #>
    try {
        $json = scoop export 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $json) {
            return $null
        }
        return $json | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-InstalledBuckets {
    <#
    .SYNOPSIS
        Get list of installed Scoop buckets
    #>
    $export = _GetScoopExport
    if (-not $export -or -not $export.buckets) {
        return @()
    }

    return @($export.buckets | ForEach-Object { $_.Name })
}

function Get-InstalledApps {
    <#
    .SYNOPSIS
        Get list of installed Scoop apps with versions
    #>
    $export = _GetScoopExport
    if (-not $export -or -not $export.apps) {
        return @()
    }

    $apps = @()
    foreach ($app in $export.apps) {
        if ($app.Info -ne "Install failed") {
            $apps += @{
                name = $app.Name
                version = $app.Version
            }
        }
    }
    return $apps
}

function Get-PackageDiff {
    <#
    .SYNOPSIS
        Calculate differences between config and installed packages
    .PARAMETER Config
        The normalized configuration
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $diff = @{
        buckets = @{
            toAdd = @()
            toRemove = @()
        }
        apps = @{
            toInstall = @()
            toRemove = @()
            toUpdate = @()
        }
    }

    if (-not $Config.packages -or (-not $Config.packages.buckets -and -not $Config.packages.apps)) {
        return $diff
    }

    $installedBuckets = Get-InstalledBuckets
    $installedApps = Get-InstalledApps

    $configBucketNames = $Config.packages.buckets | ForEach-Object { $_.name }
    $configAppNames = $Config.packages.apps | ForEach-Object { $_.name }

    foreach ($bucket in $Config.packages.buckets) {
        if ($bucket.name -notin $installedBuckets) {
            $diff.buckets.toAdd += $bucket
        }
    }

    foreach ($bucket in $installedBuckets) {
        if ($bucket -ne "main" -and $bucket -notin $configBucketNames) {
            $diff.buckets.toRemove += $bucket
        }
    }

    foreach ($app in $Config.packages.apps) {
        $installed = $installedApps | Where-Object { $_.name -eq $app.name }
        if (-not $installed) {
            $diff.apps.toInstall += $app
        }
        elseif ($app.version -and $installed.version -ne $app.version) {
            $diff.apps.toUpdate += @{
                name = $app.name
                currentVersion = $installed.version
                targetVersion = $app.version
            }
        }
    }

    foreach ($app in $installedApps) {
        if ($app.name -ne "scoop" -and $app.name -notin $configAppNames) {
            $diff.apps.toRemove += $app.name
        }
    }

    return $diff
}

function Invoke-PackageApply {
    <#
    .SYNOPSIS
        Apply package changes
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

    if (-not $Config.packages -or (-not $Config.packages.buckets -and -not $Config.packages.apps)) {
        return @{ changes = 0 }
    }

    Assert-ScoopInstalled

    $diff = Get-PackageDiff -Config $Config
    $total = $diff.buckets.toAdd.Count + $diff.buckets.toRemove.Count +
             $diff.apps.toInstall.Count + $diff.apps.toRemove.Count + $diff.apps.toUpdate.Count
    $index = 0
    $changes = 0

    foreach ($bucket in $diff.buckets.toAdd) {
        $index++
        $prefix = Format-ProgressPrefix -Index $index -Total $total
        if ($DryRun) {
            Write-Host "$prefix  + $($bucket.name)" -ForegroundColor Green -NoNewline
            Write-Host "             (would add bucket)" -ForegroundColor DarkGray
        }
        else {
            Write-Host "$prefix  + $($bucket.name)" -ForegroundColor Green -NoNewline
            try {
                if ($bucket.url) {
                    scoop bucket add $bucket.name $bucket.url 2>&1 | Out-Null
                }
                else {
                    scoop bucket add $bucket.name 2>&1 | Out-Null
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

    foreach ($bucket in $diff.buckets.toRemove) {
        $index++
        $prefix = Format-ProgressPrefix -Index $index -Total $total
        if ($DryRun) {
            Write-Host "$prefix  - $bucket" -ForegroundColor Red -NoNewline
            Write-Host "             (would remove bucket)" -ForegroundColor DarkGray
        }
        else {
            Write-Host "$prefix  - $bucket" -ForegroundColor Red -NoNewline
            try {
                scoop bucket rm $bucket 2>&1 | Out-Null
                Write-Host "             done" -ForegroundColor DarkGray
            }
            catch {
                Write-Host "             failed" -ForegroundColor Red
                throw
            }
        }
        $changes++
    }

    foreach ($app in $diff.apps.toInstall) {
        $appSpec = if ($app.version) { "$($app.name)@$($app.version)" } else { $app.name }
        $index++
        $prefix = Format-ProgressPrefix -Index $index -Total $total
        if ($DryRun) {
            Write-Host "$prefix  + $($app.name)" -ForegroundColor Green -NoNewline
            Write-Host "             (would install)" -ForegroundColor DarkGray
        }
        else {
            Write-Host "$prefix  + $($app.name)" -ForegroundColor Green -NoNewline
            try {
                _InvokeScoopInstall -AppSpec $appSpec -Silent
                if ($app.version) {
                    scoop hold $app.name 2>&1 | Out-Null
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
                scoop uninstall $app 2>&1 | Out-Null
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
                scoop unhold $app.name 2>&1 | Out-Null
                scoop uninstall $app.name 2>&1 | Out-Null
                _InvokeScoopInstall -AppSpec "$($app.name)@$($app.targetVersion)" -Silent
                scoop hold $app.name 2>&1 | Out-Null
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

function Show-PackageStatus {
    <#
    .SYNOPSIS
        Show package status differences
    .PARAMETER Config
        The normalized configuration
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    if (-not $Config.packages -or (-not $Config.packages.buckets -and -not $Config.packages.apps)) {
        return
    }

    $diff = Get-PackageDiff -Config $Config

    $hasChanges = $diff.buckets.toAdd.Count -gt 0 -or
                  $diff.buckets.toRemove.Count -gt 0 -or
                  $diff.apps.toInstall.Count -gt 0 -or
                  $diff.apps.toRemove.Count -gt 0 -or
                  $diff.apps.toUpdate.Count -gt 0

    if (-not $hasChanges) {
        return
    }

    Write-SectionHeader -Title "Packages / Scoop"

    foreach ($bucket in $diff.buckets.toAdd) {
        Write-Host "  + $($bucket.name)" -ForegroundColor Green -NoNewline
        Write-Host "             (bucket to add)" -ForegroundColor DarkGray
    }

    foreach ($bucket in $diff.buckets.toRemove) {
        Write-Host "  - $bucket" -ForegroundColor Red -NoNewline
        Write-Host "             (bucket to remove)" -ForegroundColor DarkGray
    }

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

function Install-ScoopPackage {
    <#
    .SYNOPSIS
        Install a Scoop package and update winix.yaml
    .PARAMETER AppSpec
        The app specification (app or app@version or bucket/app)
    .PARAMETER Bucket
        Optional bucket name
    .PARAMETER Config
        The current configuration
    .PARAMETER ConfigPath
        Path to winix.yaml
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppSpec,
        [string]$Bucket,
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    Assert-ScoopInstalled

    $appName = $AppSpec
    $version = $null
    $bucketName = $Bucket

    if ($AppSpec -match '^(.+)@(.+)$') {
        $appName = $Matches[1]
        $version = $Matches[2]
    }

    if ($appName -match '^(.+)/(.+)$') {
        $bucketName = $Matches[1]
        $appName = $Matches[2]
    }

    if ($bucketName) {
        $installedBuckets = Get-InstalledBuckets
        if ($bucketName -notin $installedBuckets) {
            Write-Host "Adding bucket: $bucketName"
            scoop bucket add $bucketName
        }

        $bucketExists = $Config.packages.buckets | Where-Object { $_.name -eq $bucketName }
        if (-not $bucketExists) {
            $Config.packages.buckets += @{ name = $bucketName; url = $null }
        }
    }

    $installSpec = if ($version) { "$appName@$version" } else { $appName }
    Write-Host "Installing: $installSpec"
    _InvokeScoopInstall -AppSpec $installSpec

    if ($version) {
        scoop hold $appName
    }

    $appExists = $Config.packages.apps | Where-Object { $_.name -eq $appName }
    if ($appExists) {
        $Config.packages.apps = @($Config.packages.apps | ForEach-Object {
            if ($_.name -eq $appName) {
                @{ name = $appName; version = $version }
            }
            else {
                $_
            }
        })
    }
    else {
        $Config.packages.apps += @{ name = $appName; version = $version }
    }

    Update-WinixYaml -ConfigPath $ConfigPath -Packages $Config.packages

    Write-Host "Updated winix.yaml" -ForegroundColor Green
}

function Uninstall-ScoopPackage {
    <#
    .SYNOPSIS
        Uninstall a Scoop package and update winix.yaml
    .PARAMETER AppName
        The app name to uninstall
    .PARAMETER Config
        The current configuration
    .PARAMETER ConfigPath
        Path to winix.yaml
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    Assert-ScoopInstalled

    Write-Host "Uninstalling: $AppName"
    scoop uninstall $AppName

    $Config.packages.apps = @($Config.packages.apps | Where-Object { $_.name -ne $AppName })

    Update-WinixYaml -ConfigPath $ConfigPath -Packages $Config.packages

    Write-Host "Updated winix.yaml" -ForegroundColor Green
}

function Update-ScoopPackage {
    <#
    .SYNOPSIS
        Update Scoop packages
    .PARAMETER AppName
        Optional app name to update. If not specified, updates all.
    .PARAMETER Config
        The current configuration
    #>
    param(
        [string]$AppName,
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    Assert-ScoopInstalled

    if ($AppName) {
        $pinnedApp = $Config.packages.apps | Where-Object { $_.name -eq $AppName -and $_.version }
        if ($pinnedApp) {
            Write-Warning "$AppName is pinned to version $($pinnedApp.version), skipping update"
            return
        }
        Write-Host "Updating: $AppName"
        scoop update $AppName
    }
    else {
        scoop update

        $pinnedApps = $Config.packages.apps | Where-Object { $_.version }
        $pinnedNames = $pinnedApps | ForEach-Object { $_.name }

        $installedApps = Get-InstalledApps
        foreach ($app in $installedApps) {
            if ($app.name -in $pinnedNames) {
                Write-Warning "$($app.name) is pinned, skipping update"
                continue
            }
            scoop update $app.name 2>&1 | Out-Null
        }
    }
}

function Add-ScoopBucket {
    <#
    .SYNOPSIS
        Add a Scoop bucket and update winix.yaml
    .PARAMETER BucketName
        The bucket name
    .PARAMETER BucketUrl
        Optional bucket URL
    .PARAMETER Config
        The current configuration
    .PARAMETER ConfigPath
        Path to winix.yaml
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$BucketName,
        [string]$BucketUrl,
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    Assert-ScoopInstalled

    Write-Host "Adding bucket: $BucketName"
    if ($BucketUrl) {
        scoop bucket add $BucketName $BucketUrl
    }
    else {
        scoop bucket add $BucketName
    }

    $bucketExists = $Config.packages.buckets | Where-Object { $_.name -eq $BucketName }
    if (-not $bucketExists) {
        $Config.packages.buckets += @{ name = $BucketName; url = $BucketUrl }
    }

    Update-WinixYaml -ConfigPath $ConfigPath -Packages $Config.packages

    Write-Host "Updated winix.yaml" -ForegroundColor Green
}

function Remove-ScoopBucket {
    <#
    .SYNOPSIS
        Remove a Scoop bucket and update winix.yaml
    .PARAMETER BucketName
        The bucket name
    .PARAMETER Config
        The current configuration
    .PARAMETER ConfigPath
        Path to winix.yaml
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$BucketName,
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    Assert-ScoopInstalled

    Write-Host "Removing bucket: $BucketName"
    scoop bucket rm $BucketName

    $Config.packages.buckets = @($Config.packages.buckets | Where-Object { $_.name -ne $BucketName })

    Update-WinixYaml -ConfigPath $ConfigPath -Packages $Config.packages

    Write-Host "Updated winix.yaml" -ForegroundColor Green
}

