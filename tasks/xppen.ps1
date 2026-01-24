<#
.SYNOPSIS
    XPPen driver download/install task for winix
.DESCRIPTION
    Fetches latest Windows driver info from XPPen download pages, downloads, and installs.
#>

$ErrorActionPreference = 'Stop'

function global:Get-TaskInfo {
    <#
    .SYNOPSIS
        Returns task information
    #>
    return @{
        Name        = "XPPen Drivers"
        Description = "Download and install latest XPPen Windows drivers"
        Version     = "1.0.0"
    }
}

function global:_GetInstalledXPPenDrivers {
    <#
    .SYNOPSIS
        Get installed XPPen-related drivers/apps from uninstall registry
    #>
    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $items = @()
    foreach ($path in $paths) {
        $items += Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
    }

    $drivers = @()
    foreach ($item in $items) {
        $name = $item.DisplayName
        if ($name -and $name -match '(?i)xp[- ]?pen|pentablet|pen\\s*tablet') {
            $drivers += @{
                Name    = $name
                Version = $item.DisplayVersion
            }
        }
    }
    return $drivers
}

function global:_NormalizeVersion {
    <#
    .SYNOPSIS
        Normalize a version string to an int array
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $clean = ($Version -replace '[^0-9.]', '')
    if (-not $clean) {
        return @()
    }

    $parts = @()
    foreach ($part in ($clean -split '\.')) {
        if ($part -ne '') {
            $parts += [int]$part
        }
    }
    return $parts
}

function global:_CompareVersion {
    <#
    .SYNOPSIS
        Compare two version strings
    .OUTPUTS
        1 if A > B, -1 if A < B, 0 if equal
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$A,
        [Parameter(Mandatory = $true)]
        [string]$B
    )

    $aParts = _NormalizeVersion $A
    $bParts = _NormalizeVersion $B
    $max = [Math]::Max($aParts.Count, $bParts.Count)

    for ($i = 0; $i -lt $max; $i++) {
        $aVal = if ($i -lt $aParts.Count) { $aParts[$i] } else { 0 }
        $bVal = if ($i -lt $bParts.Count) { $bParts[$i] } else { 0 }
        if ($aVal -gt $bVal) { return 1 }
        if ($aVal -lt $bVal) { return -1 }
    }

    return 0
}

function global:_GetLatestWindowsDriverInfo {
    <#
    .SYNOPSIS
        Fetch latest Windows driver info from XPPen download page
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DownloadPage
    )

    $html = (Invoke-WebRequest -Uri $DownloadPage -UseBasicParsing).Content
    $pattern = 'XPPenWin_([0-9.]+).*?data-id="(\d+)".*?data-pid="(\d+)".*?data-ext="(\w+)"'
    $matches = [regex]::Matches($html, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($matches.Count -eq 0) {
        return $null
    }

    $best = $matches[0]
    foreach ($candidate in $matches) {
        if ((_CompareVersion $candidate.Groups[1].Value $best.Groups[1].Value) -gt 0) {
            $best = $candidate
        }
    }

    $version = $best.Groups[1].Value
    $id = $best.Groups[2].Value
    $productId = $best.Groups[3].Value
    $ext = $best.Groups[4].Value

    return @{
        Name        = "XPPenWin_$version"
        Version     = $version
        Id          = $id
        Pid         = $productId
        Ext         = $ext
        DownloadUrl = "https://www.xp-pen.com/download/file.html?id=$id&pid=$productId&ext=$ext"
    }
}

function global:_FindInstallerExe {
    <#
    .SYNOPSIS
        Find installer exe in extracted driver folder
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $allExe = Get-ChildItem -Path $Path -Recurse -Filter *.exe -File -ErrorAction SilentlyContinue
    if (-not $allExe) {
        return $null
    }

    $preferred = $allExe | Where-Object {
        $_.Name -match '(?i)xp-?pen|pentablet|pen\\s*tablet'
    }

    $candidates = if ($preferred) { $preferred } else { $allExe }
    return $candidates | Sort-Object Length -Descending | Select-Object -First 1
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

    $devices = @()
    if ($Config.devices) {
        $devices = @($Config.devices)
    }

    if ($devices.Count -eq 0) {
        $status.ToInstall += "No devices configured"
        return $status
    }

    $installed = _GetInstalledXPPenDrivers
    $installedVersions = @($installed | ForEach-Object { $_.Version } | Where-Object { $_ })

    foreach ($device in $devices) {
        $name = $device.name
        $page = $device.download_page
        $label = if ($name) { $name } else { $page }

        if (-not $page) {
            $status.ToInstall += "${label}: download_page missing"
            continue
        }

        $info = $null
        try {
            $info = _GetLatestWindowsDriverInfo $page
        }
        catch {
            $info = $null
        }

        if (-not $info) {
            $status.ToInstall += "${label}: latest Windows driver not found"
            continue
        }

        $isInstalled = $false
        foreach ($ver in $installedVersions) {
            if ((_CompareVersion $ver $info.Version) -ge 0) {
                $isInstalled = $true
                break
            }
        }

        if ($isInstalled) {
            $status.UpToDate += "${label}: $($info.Name)"
        }
        else {
            $status.ToInstall += "${label}: $($info.Name)"
        }
    }

    return $status
}

function global:Invoke-TaskApply {
    <#
    .SYNOPSIS
        Download and install XPPen drivers
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
        removed   = @()
    }

    $devices = @()
    if ($Config.devices) {
        $devices = @($Config.devices)
    }
    if ($devices.Count -eq 0) {
        Write-Warning "No devices configured"
        return $result
    }

    $downloadRoot = if ($Config.download_root) { $Config.download_root } else { Join-Path $env:TEMP "winix\\xppen" }
    $keepDownloads = $false
    if ($Config.keep_downloads -ne $null) {
        $keepDownloads = [bool]$Config.keep_downloads
    }

    $installArgs = @()
    if ($Config.install_args) {
        if ($Config.install_args -is [string]) {
            $installArgs = @($Config.install_args)
        }
        else {
            $installArgs = @($Config.install_args)
        }
    }

    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
    }

    $driverMap = @{}
    foreach ($device in $devices) {
        $page = $device.download_page
        if (-not $page) {
            continue
        }

        $info = _GetLatestWindowsDriverInfo $page
        if (-not $info) {
            Write-Warning "Latest Windows driver not found for $page"
            continue
        }

        if (-not $driverMap.ContainsKey($info.DownloadUrl)) {
            $driverMap[$info.DownloadUrl] = $info
        }
    }

    foreach ($driver in $driverMap.Values) {
        $zipName = "$($driver.Name).$($driver.Ext)"
        $zipPath = Join-Path $downloadRoot $zipName
        $extractPath = Join-Path $downloadRoot $driver.Name

        Write-Host "    Downloading: $($driver.Name)" -ForegroundColor DarkGray
        if (-not $DryRun) {
            Invoke-WebRequest -Uri $driver.DownloadUrl -OutFile $zipPath -UseBasicParsing
        }

        Write-Host "    Extracting: $zipName" -ForegroundColor DarkGray
        if (-not $DryRun) {
            if (Test-Path $extractPath) {
                Remove-Item -Path $extractPath -Recurse -Force
            }
            Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        }

        $installer = $null
        if (-not $DryRun) {
            $installer = _FindInstallerExe $extractPath
        }

        if (-not $DryRun -and -not $installer) {
            Write-Error "Installer exe not found in $extractPath"
        }

        $displayCmd = if ($installArgs.Count -gt 0) {
            "$($installer.FullName) $($installArgs -join ' ')"
        }
        else {
            $installer.FullName
        }
        Write-Host "    Running: $displayCmd" -ForegroundColor DarkGray

        if (-not $DryRun) {
            Start-Process -FilePath $installer.FullName -ArgumentList $installArgs -Wait
            $result.installed += $driver.Name
            Write-Host "    Installed: $($driver.Name)" -ForegroundColor Green
        }

        if (-not $DryRun -and -not $keepDownloads) {
            Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        }
    }

    return $result
}

function global:Invoke-TaskCleanup {
    <#
    .SYNOPSIS
        Clean up task-specific helper functions
    #>
    Remove-Item -Path "Function:\_GetInstalledXPPenDrivers" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_NormalizeVersion" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_CompareVersion" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetLatestWindowsDriverInfo" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_FindInstallerExe" -ErrorAction SilentlyContinue
}
