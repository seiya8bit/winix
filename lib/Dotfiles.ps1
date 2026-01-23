<#
.SYNOPSIS
    Dotfiles management module for winix
.DESCRIPTION
    Manages dotfiles using copy-based approach with full sync support
#>

$ErrorActionPreference = 'Stop'

function _GetRelativePath {
    <#
    .SYNOPSIS
        Get relative path from source directory
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FullPath,
        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    $fullPathNorm = (Resolve-Path $FullPath).Path
    $basePathNorm = (Resolve-Path $BasePath).Path

    if ($fullPathNorm.StartsWith($basePathNorm, [StringComparison]::OrdinalIgnoreCase)) {
        $relative = $fullPathNorm.Substring($basePathNorm.Length)
        return $relative.TrimStart('\', '/')
    }

    return $FullPath
}


function _GetSourceFiles {
    <#
    .SYNOPSIS
        Get all files and empty directories from source
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )

    if (-not (Test-Path $SourcePath)) {
        return @()
    }

    $items = @()

    $files = Get-ChildItem -Path $SourcePath -Recurse -File
    foreach ($file in $files) {
        $relativePath = _GetRelativePath -FullPath $file.FullName -BasePath $SourcePath
        $items += @{
            type = "file"
            relativePath = $relativePath
            sourcePath = $file.FullName
        }
    }

    $dirs = Get-ChildItem -Path $SourcePath -Recurse -Directory
    foreach ($dir in $dirs) {
        $children = Get-ChildItem -Path $dir.FullName -Force
        if ($children.Count -eq 0) {
            $relativePath = _GetRelativePath -FullPath $dir.FullName -BasePath $SourcePath
            $items += @{
                type = "directory"
                relativePath = $relativePath
                sourcePath = $dir.FullName
            }
        }
    }

    return $items
}

function Get-DotfilesDiff {
    <#
    .SYNOPSIS
        Calculate differences between source and target
    .PARAMETER Config
        The normalized configuration
    .PARAMETER State
        The current state
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [Parameter(Mandatory = $true)]
        [hashtable]$State
    )

    $diff = @{
        toAdd = @()
        toUpdate = @()
        toRemove = @()
        toTrack = @()  # Files that exist at target but aren't in state
    }

    if (-not $Config.dotfiles) {
        foreach ($item in $State.dotfiles) {
            $fullPath = Expand-TildePath $item
            $isDir = $item.EndsWith("/")
            $diff.toRemove += @{
                tildePath = $item
                fullPath = $fullPath
                isDirectory = $isDir
            }
        }
        return $diff
    }

    $sourcePath = $Config.dotfiles.source
    $targetBase = $Config.dotfiles.target

    if (-not (Test-Path $sourcePath)) {
        return $diff
    }

    $sourceItems = _GetSourceFiles -SourcePath $sourcePath

    $newTildePaths = @()

    foreach ($item in $sourceItems) {
        $targetPath = Join-Path $targetBase $item.relativePath
        $targetPath = [Environment]::ExpandEnvironmentVariables($targetPath)
        $tildePath = Normalize-TildePath $targetPath

        if ($item.type -eq "directory") {
            $tildePath = $tildePath + "/"
        }

        $newTildePaths += $tildePath

        if ($item.type -eq "file") {
            if (-not (Test-Path $targetPath)) {
                $diff.toAdd += @{
                    sourcePath = $item.sourcePath
                    targetPath = $targetPath
                    tildePath = $tildePath
                    relativePath = $item.relativePath
                }
            }
            else {
                $sourceHash = Get-WinixFileHash -Path $item.sourcePath
                $targetHash = Get-WinixFileHash -Path $targetPath
                if ($sourceHash -ne $targetHash) {
                    $diff.toUpdate += @{
                        sourcePath = $item.sourcePath
                        targetPath = $targetPath
                        tildePath = $tildePath
                        relativePath = $item.relativePath
                    }
                }
                elseif ($tildePath -notin $State.dotfiles) {
                    # File exists with same content but not tracked in state
                    $diff.toTrack += @{
                        tildePath = $tildePath
                    }
                }
            }
        }
        elseif ($item.type -eq "directory") {
            if (-not (Test-Path $targetPath)) {
                $diff.toAdd += @{
                    sourcePath = $item.sourcePath
                    targetPath = $targetPath
                    tildePath = $tildePath
                    relativePath = $item.relativePath
                    isDirectory = $true
                }
            }
        }
    }

    foreach ($stateItem in $State.dotfiles) {
        if ($stateItem -notin $newTildePaths) {
            $fullPath = Expand-TildePath $stateItem
            $isDir = $stateItem.EndsWith("/")
            $diff.toRemove += @{
                tildePath = $stateItem
                fullPath = $fullPath
                isDirectory = $isDir
            }
        }
    }

    return $diff
}

function Invoke-DotfilesApply {
    <#
    .SYNOPSIS
        Apply dotfiles changes
    .PARAMETER Config
        The normalized configuration
    .PARAMETER State
        The current state (will be modified)
    .PARAMETER DryRun
        If set, only show what would be done
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        [switch]$DryRun
    )

    $diff = Get-DotfilesDiff -Config $Config -State $State
    $changes = 0

    foreach ($item in $diff.toRemove) {
        if ($DryRun) {
            Write-Host "  - $($item.tildePath)" -ForegroundColor Red -NoNewline
            Write-Host "    (would remove)" -ForegroundColor DarkGray
        }
        else {
            Write-Host "  - $($item.tildePath)" -ForegroundColor Red -NoNewline
            try {
                if (Test-Path $item.fullPath) {
                    if ($item.isDirectory) {
                        Remove-Item -Path $item.fullPath -Force -Recurse
                    }
                    else {
                        Remove-Item -Path $item.fullPath -Force
                    }
                }
                Remove-DotfileFromState -State $State -Path $item.tildePath
                Write-Host "    done" -ForegroundColor DarkGray
            }
            catch {
                Write-Host "    failed" -ForegroundColor Red
                throw
            }
        }
        $changes++
    }

    foreach ($item in $diff.toAdd) {
        if ($DryRun) {
            Write-Host "  + $($item.tildePath)" -ForegroundColor Green -NoNewline
            Write-Host "    (would add)" -ForegroundColor DarkGray
        }
        else {
            Write-Host "  + $($item.tildePath)" -ForegroundColor Green -NoNewline
            try {
                $targetDir = Split-Path $item.targetPath -Parent
                if (-not (Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }

                if ($item.isDirectory) {
                    New-Item -ItemType Directory -Path $item.targetPath -Force | Out-Null
                }
                else {
                    Copy-Item -Path $item.sourcePath -Destination $item.targetPath -Force
                }

                Add-DotfileToState -State $State -Path $item.tildePath
                Write-Host "    done" -ForegroundColor DarkGray
            }
            catch {
                Write-Host "    failed" -ForegroundColor Red
                throw
            }
        }
        $changes++
    }

    foreach ($item in $diff.toUpdate) {
        if ($DryRun) {
            Write-Host "  ~ $($item.tildePath)" -ForegroundColor Yellow -NoNewline
            Write-Host "    (would update)" -ForegroundColor DarkGray
        }
        else {
            Write-Host "  ~ $($item.tildePath)" -ForegroundColor Yellow -NoNewline
            try {
                Copy-Item -Path $item.sourcePath -Destination $item.targetPath -Force
                # Ensure the file is tracked in state (in case it wasn't before)
                Add-DotfileToState -State $State -Path $item.tildePath
                Write-Host "    done" -ForegroundColor DarkGray
            }
            catch {
                Write-Host "    failed" -ForegroundColor Red
                throw
            }
        }
        $changes++
    }

    # Track files that exist but aren't in state (no file changes needed)
    foreach ($item in $diff.toTrack) {
        if ($DryRun) {
            Write-Host "  = $($item.tildePath)" -ForegroundColor DarkGray -NoNewline
            Write-Host "    (would track)" -ForegroundColor DarkGray
        }
        else {
            Write-Host "  = $($item.tildePath)" -ForegroundColor DarkGray -NoNewline
            Add-DotfileToState -State $State -Path $item.tildePath
            Write-Host "    done" -ForegroundColor DarkGray
        }
        $changes++
    }

    return @{ changes = $changes }
}

function Show-DotfilesStatus {
    <#
    .SYNOPSIS
        Show dotfiles status differences
    .PARAMETER Config
        The normalized configuration
    .PARAMETER State
        The current state
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [Parameter(Mandatory = $true)]
        [hashtable]$State
    )

    $diff = Get-DotfilesDiff -Config $Config -State $State

    $hasChanges = $diff.toAdd.Count -gt 0 -or
                  $diff.toUpdate.Count -gt 0 -or
                  $diff.toRemove.Count -gt 0 -or
                  $diff.toTrack.Count -gt 0

    if (-not $hasChanges) {
        return
    }

    Write-SectionHeader -Title "Dotfiles"

    foreach ($item in $diff.toAdd) {
        Write-Host "  + $($item.tildePath)" -ForegroundColor Green
    }

    foreach ($item in $diff.toUpdate) {
        Write-Host "  ~ $($item.tildePath)" -ForegroundColor Yellow
    }

    foreach ($item in $diff.toTrack) {
        Write-Host "  = $($item.tildePath)" -ForegroundColor DarkGray
    }

    foreach ($item in $diff.toRemove) {
        Write-Host "  - $($item.tildePath)" -ForegroundColor Red
    }
}

