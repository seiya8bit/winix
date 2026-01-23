<#
.SYNOPSIS
    Common utilities for winix
.DESCRIPTION
    Shared helpers for paths, hashing, command checks, and progress formatting
#>

$ErrorActionPreference = 'Stop'

if (-not $script:WINIX_ROOT) {
    $script:WINIX_ROOT = Split-Path $PSScriptRoot -Parent
}

function Get-WinixRoot {
    <#
    .SYNOPSIS
        Return winix repository root directory
    #>
    return $script:WINIX_ROOT
}

function Get-WinixConfigPath {
    <#
    .SYNOPSIS
        Return default winix.yaml path
    #>
    return Join-Path (Get-WinixRoot) "winix.yaml"
}

function Ensure-Directory {
    <#
    .SYNOPSIS
        Ensure a directory exists
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Expand-WinixPath {
    <#
    .SYNOPSIS
        Expand ~ and environment variables in a path
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $expanded = $Path -replace '^~', $env:USERPROFILE
    return [Environment]::ExpandEnvironmentVariables($expanded)
}

function Normalize-TildePath {
    <#
    .SYNOPSIS
        Convert a full path to tilde notation
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $userProfile = $env:USERPROFILE
    if ($Path.StartsWith($userProfile, [StringComparison]::OrdinalIgnoreCase)) {
        return "~" + $Path.Substring($userProfile.Length)
    }
    return $Path
}

function Expand-TildePath {
    <#
    .SYNOPSIS
        Expand tilde notation to a full path
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($Path.StartsWith("~")) {
        return $env:USERPROFILE + $Path.Substring(1)
    }
    return $Path
}

function Get-WinixFileHash {
    <#
    .SYNOPSIS
        Get SHA256 hash of a file (or null if missing)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    $hash = Get-FileHash -Path $Path -Algorithm SHA256
    return $hash.Hash
}

function Format-ProgressPrefix {
    <#
    .SYNOPSIS
        Format progress prefix like [01/10]
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$Index,
        [Parameter(Mandatory = $true)]
        [int]$Total
    )

    $width = $Total.ToString().Length
    $idx = $Index.ToString().PadLeft($width, '0')
    return "[{0}/{1}]" -f $idx, $Total
}

function Test-CommandAvailable {
    <#
    .SYNOPSIS
        Check if a command exists
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    return $null -ne $command
}

function Assert-CommandAvailable {
    <#
    .SYNOPSIS
        Assert that a command exists
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not (Test-CommandAvailable -Name $Name)) {
        Write-Error $Message
        throw $Message
    }
}

function Test-GsudoInstalled {
    <#
    .SYNOPSIS
        Check if gsudo is installed
    #>
    return Test-CommandAvailable -Name "gsudo"
}

function Assert-GsudoInstalled {
    <#
    .SYNOPSIS
        Assert that gsudo is installed
    #>
    if (-not (Test-GsudoInstalled)) {
        Write-Error "gsudo is required for machine-level environment variable operations. Install it via Scoop."
        throw "gsudo not installed"
    }
}
