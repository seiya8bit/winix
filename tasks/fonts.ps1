<#
.SYNOPSIS
    Font installation task for winix
.DESCRIPTION
    Installs fonts from a source directory to user fonts folder
#>

$ErrorActionPreference = 'Stop'

function global:Get-TaskInfo {
    <#
    .SYNOPSIS
        Returns task information
    #>
    return @{
        Name        = "Fonts"
        Description = "Install fonts from source directory"
        Version     = "1.0.0"
    }
}

function global:_ExpandFontPath {
    <#
    .SYNOPSIS
        Expand path with ~ and environment variables
    .PARAMETER Path
        Path to expand
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # Expand ~ to USERPROFILE
    $expanded = $Path -replace '^~', $env:USERPROFILE

    # Expand $env:VAR format
    $expanded = [regex]::Replace($expanded, '\$env:(\w+)', {
        param($match)
        [Environment]::GetEnvironmentVariable($match.Groups[1].Value)
    })

    # Expand %VAR% format
    $expanded = [Environment]::ExpandEnvironmentVariables($expanded)

    return $expanded
}

function global:_GetUserFontsDir {
    <#
    .SYNOPSIS
        Get user fonts directory path
    #>
    return Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
}

function global:_GetFontRegistryPath {
    <#
    .SYNOPSIS
        Get user font registry path
    #>
    return "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
}

function global:_GetSourceFonts {
    <#
    .SYNOPSIS
        Get list of font files from source directory
    .PARAMETER SourceDir
        Source directory path
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDir
    )

    if (-not (Test-Path $SourceDir)) {
        return @()
    }

    $fontExtensions = @("*.ttf", "*.otf", "*.ttc", "*.woff", "*.woff2")
    $fonts = @()

    foreach ($ext in $fontExtensions) {
        $files = Get-ChildItem -Path $SourceDir -Filter $ext -Recurse -File -ErrorAction SilentlyContinue
        $fonts += $files
    }

    return $fonts
}

function global:_GetUniqueFontsByName {
    <#
    .SYNOPSIS
        Return a unique list of fonts by file name.
    .DESCRIPTION
        If duplicate file names exist, keep the first and ignore the rest.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IEnumerable]$Fonts
    )

    $seen = @{}
    $unique = @()
    foreach ($font in $Fonts) {
        if (-not $seen.ContainsKey($font.Name)) {
            $seen[$font.Name] = $true
            $unique += $font
        }
    }
    return $unique
}

function global:_GetDuplicateFontNames {
    <#
    .SYNOPSIS
        Get duplicate font file names from a list.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IEnumerable]$Fonts
    )

    $counts = @{}
    foreach ($font in $Fonts) {
        if ($counts.ContainsKey($font.Name)) {
            $counts[$font.Name] += 1
        }
        else {
            $counts[$font.Name] = 1
        }
    }

    $dupes = @()
    foreach ($name in $counts.Keys) {
        if ($counts[$name] -gt 1) {
            $dupes += $name
        }
    }
    return $dupes
}

function global:_GetInstalledUserFonts {
    <#
    .SYNOPSIS
        Get list of installed user fonts from registry
    #>
    $regPath = _GetFontRegistryPath

    if (-not (Test-Path $regPath)) {
        return @{}
    }

    $fonts = @{}
    $regKey = Get-Item -Path $regPath -ErrorAction SilentlyContinue
    if ($regKey) {
        foreach ($name in $regKey.GetValueNames()) {
            $value = $regKey.GetValue($name)
            $fonts[$name] = $value
        }
    }

    return $fonts
}

function global:_GetFontName {
    <#
    .SYNOPSIS
        Get font display name from file
    .PARAMETER FontPath
        Path to font file
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FontPath
    )

    # Use file name without extension as display name
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FontPath)
    $extension = [System.IO.Path]::GetExtension($FontPath).ToLower()

    $fontType = switch ($extension) {
        ".ttf" { "(TrueType)" }
        ".otf" { "(OpenType)" }
        ".ttc" { "(TrueType)" }
        default { "(TrueType)" }
    }

    return "$fileName $fontType"
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

    if (-not $Config.source) {
        return $status
    }

    $sourceDir = _ExpandFontPath -Path $Config.source
    if (-not [System.IO.Path]::IsPathRooted($sourceDir)) {
        $sourceDir = Join-Path $PSScriptRoot "..\$sourceDir"
    }
    $sourceDir = [System.IO.Path]::GetFullPath($sourceDir)

    $sourceFonts = _GetSourceFonts -SourceDir $sourceDir
    $duplicateNames = _GetDuplicateFontNames -Fonts $sourceFonts
    if ($duplicateNames.Count -gt 0) {
        foreach ($name in $duplicateNames) {
            $status.ToInstall += "duplicate font filename (skipped extra): $name"
        }
    }
    $sourceFonts = _GetUniqueFontsByName -Fonts $sourceFonts
    $installedFonts = _GetInstalledUserFonts
    $userFontsDir = _GetUserFontsDir

    $stateItems = @()
    if ($TaskState.items) {
        $stateItems = @($TaskState.items)
    }

    # Check fonts in source
    foreach ($font in $sourceFonts) {
        $fontName = _GetFontName -FontPath $font.FullName
        $targetPath = Join-Path $userFontsDir $font.Name
        $isInState = $font.Name -in $stateItems

        if ($installedFonts.Values -contains $targetPath) {
            if ($isInState) {
                $status.UpToDate += $font.Name
            }
            else {
                $status.ToInstall += "$($font.Name) (track existing)"
            }
        }
        else {
            $status.ToInstall += $font.Name
        }
    }

    # Check fonts in state but not in source (ToRemove)
    $sourceFontNames = @($sourceFonts | ForEach-Object { $_.Name })
    foreach ($fontFile in $stateItems) {
        if ($fontFile -notin $sourceFontNames) {
            $status.ToRemove += $fontFile
        }
    }

    return $status
}

function global:Invoke-TaskApply {
    <#
    .SYNOPSIS
        Install/uninstall fonts
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

    if (-not $Config.source) {
        return $result
    }

    $sourceDir = _ExpandFontPath -Path $Config.source
    if (-not [System.IO.Path]::IsPathRooted($sourceDir)) {
        $sourceDir = Join-Path $PSScriptRoot "..\$sourceDir"
    }
    $sourceDir = [System.IO.Path]::GetFullPath($sourceDir)

    $sourceFonts = _GetSourceFonts -SourceDir $sourceDir
    $duplicateNames = _GetDuplicateFontNames -Fonts $sourceFonts
    if ($duplicateNames.Count -gt 0) {
        foreach ($name in $duplicateNames) {
            Write-Warning "Duplicate font filename detected, skipping extras: $name"
        }
    }
    $sourceFonts = _GetUniqueFontsByName -Fonts $sourceFonts
    $installedFonts = _GetInstalledUserFonts
    $userFontsDir = _GetUserFontsDir
    $regPath = _GetFontRegistryPath

    $stateItems = @()
    if ($TaskState.items) {
        $stateItems = @($TaskState.items)
    }

    # Ensure user fonts directory exists
    if (-not (Test-Path $userFontsDir)) {
        if (-not $DryRun) {
            New-Item -ItemType Directory -Path $userFontsDir -Force | Out-Null
        }
    }

    # Ensure registry key exists
    if (-not (Test-Path $regPath) -and -not $DryRun) {
        New-Item -Path $regPath -Force | Out-Null
    }

    # Install fonts from source
    foreach ($font in $sourceFonts) {
        $fontName = _GetFontName -FontPath $font.FullName
        $targetPath = Join-Path $userFontsDir $font.Name
        $isInState = $font.Name -in $stateItems
        $isInstalled = $installedFonts.Values -contains $targetPath

        if (-not $isInstalled) {
            if (-not $DryRun) {
                # Copy font file
                Copy-Item -Path $font.FullName -Destination $targetPath -Force
                Write-Host "    Copied: $($font.Name)" -ForegroundColor DarkGray

                # Register font
                Set-ItemProperty -Path $regPath -Name $fontName -Value $targetPath -Type String
                Write-Host "    Registered: $fontName" -ForegroundColor DarkGray
            }
            if (-not $DryRun) {
                $result.installed += $font.Name
            }
        }
        elseif (-not $isInState) {
            # Already installed but not tracked yet.
            if (-not $DryRun) {
                $result.installed += $font.Name
            }
        }
    }

    # Uninstall fonts removed from source
    $sourceFontNames = @($sourceFonts | ForEach-Object { $_.Name })
    foreach ($fontFile in $stateItems) {
        if ($fontFile -notin $sourceFontNames) {
            $targetPath = Join-Path $userFontsDir $fontFile

            if (-not $DryRun) {
                # Find and remove registry entry
                $installedFonts = _GetInstalledUserFonts
                foreach ($name in $installedFonts.Keys) {
                    if ($installedFonts[$name] -eq $targetPath) {
                        Remove-ItemProperty -Path $regPath -Name $name -ErrorAction SilentlyContinue
                        Write-Host "    Unregistered: $name" -ForegroundColor DarkGray
                        break
                    }
                }

                # Remove font file
                if (Test-Path $targetPath) {
                    Remove-Item -Path $targetPath -Force -ErrorAction SilentlyContinue
                    Write-Host "    Removed: $fontFile" -ForegroundColor DarkGray
                }
            }
            $result.removed += $fontFile
        }
    }

    return $result
}

function global:Invoke-TaskCleanup {
    <#
    .SYNOPSIS
        Clean up task-specific helper functions
    #>
    Remove-Item -Path "Function:\_ExpandFontPath" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetUserFontsDir" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetFontRegistryPath" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetSourceFonts" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetInstalledUserFonts" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetFontName" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetUniqueFontsByName" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetDuplicateFontNames" -ErrorAction SilentlyContinue
}
