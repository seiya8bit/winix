<#
.SYNOPSIS
    AviUtl2 (AviUtl ExEdit2) installation task for winix
.DESCRIPTION
    Fetches latest AviUtl2 beta release from the official download page,
    downloads it, and installs via installer.
#>

$ErrorActionPreference = 'Stop'

function global:Get-TaskInfo {
    <#
    .SYNOPSIS
        Returns task information
    #>
    return @{
        Name        = "AviUtl2"
        Description = "Download and install the latest AviUtl2 beta release"
        Version     = "1.0.0"
    }
}

function global:_NormalizeBetaVersion {
    <#
    .SYNOPSIS
        Normalize a beta version string (e.g., 28a) into numeric parts
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    if ($Version -notmatch '^(\d+)([a-z]?)$') {
        return @()
    }

    $num = [int]$Matches[1]
    $suffix = $Matches[2]
    $suffixValue = 0
    if ($suffix) {
        $suffixValue = ([int][char]$suffix) - ([int][char]'a') + 1
        if ($suffixValue -lt 0) { $suffixValue = 0 }
    }

    return @($num, $suffixValue)
}

function global:_CompareBetaVersion {
    <#
    .SYNOPSIS
        Compare two beta version strings
    .OUTPUTS
        1 if A > B, -1 if A < B, 0 if equal
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$A,
        [Parameter(Mandatory = $true)]
        [string]$B
    )

    $aParts = _NormalizeBetaVersion $A
    $bParts = _NormalizeBetaVersion $B
    if ($aParts.Count -eq 0 -and $bParts.Count -eq 0) { return 0 }
    if ($aParts.Count -eq 0) { return -1 }
    if ($bParts.Count -eq 0) { return 1 }

    if ($aParts[0] -gt $bParts[0]) { return 1 }
    if ($aParts[0] -lt $bParts[0]) { return -1 }
    if ($aParts[1] -gt $bParts[1]) { return 1 }
    if ($aParts[1] -lt $bParts[1]) { return -1 }
    return 0
}

function global:_ExtractBetaVersion {
    <#
    .SYNOPSIS
        Extract beta version string from text
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    if ($Text -match '(?i)beta\s*([0-9]+[a-z]?)') {
        return $Matches[1]
    }

    return $null
}

function global:_GetLatestAviUtl2Info {
    <#
    .SYNOPSIS
        Fetch latest AviUtl2 installer download link from the official page
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DownloadPage
    )

    $html = (Invoke-WebRequest -Uri $DownloadPage -UseBasicParsing).Content
    $baseUri = [System.Uri]$DownloadPage

    $installerMatches = [regex]::Matches(
        $html,
        '(?i)href="(?<href>[^"]*AviUtl2beta(?<ver>\d+[a-z]?)_setup\.exe)"'
    )

    if ($installerMatches.Count -eq 0) {
        return $null
    }

    $latestInstaller = $null
    foreach ($match in $installerMatches) {
        $ver = $match.Groups['ver'].Value
        $href = $match.Groups['href'].Value
        $url = (New-Object System.Uri($baseUri, $href)).AbsoluteUri
        $candidate = [pscustomobject]@{ Version = $ver; Url = $url }

        if (-not $latestInstaller -or (_CompareBetaVersion $ver $latestInstaller.Version) -gt 0) {
            $latestInstaller = $candidate
        }
    }

    return @{
        Version      = $latestInstaller.Version
        InstallerUrl = $latestInstaller.Url
        Page         = $DownloadPage
    }
}

function global:_GetInstalledAviUtl2 {
    <#
    .SYNOPSIS
        Get installed AviUtl2 entries from uninstall registry
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

    $matches = @()
    foreach ($item in $items) {
        $name = $item.DisplayName
        if ($name -and $name -match '(?i)AviUtl\s*ExEdit2|AviUtl2') {
            $matches += @{
                Name    = $name
                Version = $item.DisplayVersion
            }
        }
    }

    return $matches
}

function global:_GetInstalledAviUtl2Version {
    <#
    .SYNOPSIS
        Get latest installed AviUtl2 beta version from registry entries
    #>
    $installed = _GetInstalledAviUtl2
    if (-not $installed -or $installed.Count -eq 0) {
        return $null
    }

    $versions = @()
    foreach ($item in $installed) {
        $ver = $null
        if ($item.Version) {
            $ver = _ExtractBetaVersion $item.Version
        }
        if (-not $ver -and $item.Name) {
            $ver = _ExtractBetaVersion $item.Name
        }
        if ($ver) {
            $versions += $ver
        }
    }

    if ($versions.Count -eq 0) {
        return $null
    }

    $latest = $versions[0]
    foreach ($ver in $versions) {
        if ((_CompareBetaVersion $ver $latest) -gt 0) {
            $latest = $ver
        }
    }
    return $latest
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

    $downloadPage = if ($Config.download_page) { $Config.download_page } else { "https://spring-fragrance.mints.ne.jp/aviutl/" }

    $info = $null
    try {
        $info = _GetLatestAviUtl2Info $downloadPage
    }
    catch {
        $info = $null
    }

    if (-not $info) {
        $status.ToInstall += "AviUtl2: latest version not found"
        return $status
    }

    $latestLabel = "AviUtl2 beta$($info.Version)"
    $installedVersion = _GetInstalledAviUtl2Version

    if ($installedVersion) {
        if ((_CompareBetaVersion $installedVersion $info.Version) -ge 0) {
            $status.UpToDate += $latestLabel
        }
        else {
            $status.ToInstall += $latestLabel
        }
    }
    else {
        $installed = _GetInstalledAviUtl2
        if ($installed -and $installed.Count -gt 0) {
            $status.ToInstall += "AviUtl2: installed version unknown (reinstall to track latest)"
        }
        else {
            $status.ToInstall += $latestLabel
        }
    }

    return $status
}

function global:Invoke-TaskApply {
    <#
    .SYNOPSIS
        Download and install AviUtl2
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

    $downloadPage = if ($Config.download_page) { $Config.download_page } else { "https://spring-fragrance.mints.ne.jp/aviutl/" }

    $info = _GetLatestAviUtl2Info $downloadPage
    if (-not $info) {
        Write-Error "Latest AviUtl2 version not found from $downloadPage"
    }

    $downloadRoot = Join-Path $env:TEMP "winix\aviutl2"

    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
    }

    $fileName = [System.IO.Path]::GetFileName($info.InstallerUrl)
    $downloadPath = Join-Path $downloadRoot $fileName

    Write-Host "    Downloading: $fileName" -ForegroundColor DarkGray
    if (-not $DryRun) {
        Invoke-WebRequest -Uri $info.InstallerUrl -OutFile $downloadPath -UseBasicParsing
    }

    Write-Host "    Running: $downloadPath" -ForegroundColor DarkGray
    if (-not $DryRun) {
        Start-Process -FilePath $downloadPath -Wait
        $result.installed += "AviUtl2 beta$($info.Version)"
        Write-Host "    Installed: AviUtl2 beta$($info.Version)" -ForegroundColor Green
    }

    # Clean up temporary files
    if (-not $DryRun) {
        Remove-Item -Path $downloadRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    return $result
}

function global:Invoke-TaskCleanup {
    <#
    .SYNOPSIS
        Clean up task-specific helper functions
    #>
    Remove-Item -Path "Function:\_NormalizeBetaVersion" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_CompareBetaVersion" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_ExtractBetaVersion" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetLatestAviUtl2Info" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetInstalledAviUtl2" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetInstalledAviUtl2Version" -ErrorAction SilentlyContinue
}
