<#
.SYNOPSIS
    UI helpers for winix
.DESCRIPTION
    Centralized output formatting for console UI
#>

$ErrorActionPreference = 'Stop'

function Write-UiBanner {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [string]$Subtitle
    )

    Write-Host ""
    Write-Host ("==== {0} ====" -f $Title) -ForegroundColor Cyan
    if ($Subtitle) {
        Write-Host $Subtitle -ForegroundColor DarkGray
    }
}

function Write-SectionHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    Write-Host ""
    Write-Host ("-- {0} --" -f $Title) -ForegroundColor Cyan
}
