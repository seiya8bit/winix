<#
.SYNOPSIS
    Bootstrap script for winix
.DESCRIPTION
    Installs Scoop, powershell-yaml, registers winix command, and runs initial apply
#>

$ErrorActionPreference = 'Stop'

$script:ScriptDir = $PSScriptRoot

Write-Host "winix bootstrap" -ForegroundColor Cyan
Write-Host ""

$scoopInstalled = Get-Command scoop -ErrorAction SilentlyContinue
if (-not $scoopInstalled) {
    Write-Host "Installing Scoop..." -ForegroundColor Yellow
    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
        Write-Host "Scoop installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install Scoop: $_"
        exit 1
    }
}
else {
    Write-Host "Scoop is already installed." -ForegroundColor Green
}

$psYamlInstalled = Get-Module -ListAvailable -Name powershell-yaml
if (-not $psYamlInstalled) {
    Write-Host "Installing powershell-yaml module..." -ForegroundColor Yellow
    try {
        Install-Module -Name powershell-yaml -Scope CurrentUser -Force -AllowClobber
        Write-Host "powershell-yaml installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install powershell-yaml: $_"
        exit 1
    }
}
else {
    Write-Host "powershell-yaml is already installed." -ForegroundColor Green
}

$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}

$winixPath = Join-Path $script:ScriptDir "winix.ps1"
$winixFunction = @"

# winix command
function winix {
    & '$winixPath' @args
}
"@

$profileContent = Get-Content -Path $PROFILE -Raw -ErrorAction SilentlyContinue
if (-not $profileContent) {
    $profileContent = ""
}

if ($profileContent -notmatch "function winix") {
    Write-Host "Registering winix command to PowerShell profile..." -ForegroundColor Yellow
    Add-Content -Path $PROFILE -Value $winixFunction
    Write-Host "winix command registered." -ForegroundColor Green
}
else {
    Write-Host "winix command is already registered." -ForegroundColor Green
}

. $PROFILE 2>$null

# Check if encrypted_files are configured
$configPath = Join-Path $script:ScriptDir "winix.yaml"
$hasEncryptedFiles = $false
if (Test-Path $configPath) {
    $configContent = Get-Content -Path $configPath -Raw
    if ($configContent -match "encrypted_files:") {
        $hasEncryptedFiles = $true
    }
}

# If encrypted files are configured, setup Bitwarden first
if ($hasEncryptedFiles) {
    Write-Host ""
    Write-Host "Encrypted files detected. Setting up Bitwarden..." -ForegroundColor Cyan

    # Install bitwarden-cli if not installed
    $bwInstalled = Get-Command bw -ErrorAction SilentlyContinue
    if (-not $bwInstalled) {
        Write-Host "Installing bitwarden-cli..." -ForegroundColor Yellow
        scoop install bitwarden-cli
    }

    # Check Bitwarden status
    $bwStatus = bw status 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue

    if (-not $bwStatus -or $bwStatus.status -eq "unauthenticated") {
        Write-Host ""
        Write-Host "Please login to Bitwarden:" -ForegroundColor Yellow
        bw login
        $bwStatus = bw status 2>&1 | ConvertFrom-Json
    }

    if ($bwStatus.status -eq "locked") {
        Write-Host ""
        Write-Host "Unlocking Bitwarden vault..." -ForegroundColor Yellow
        $env:BW_SESSION = $(bw unlock --raw)
        if (-not $env:BW_SESSION) {
            Write-Warning "Failed to unlock Bitwarden. Encrypted files will be skipped."
        }
        else {
            Write-Host "Bitwarden unlocked." -ForegroundColor Green
        }
    }
    elseif ($bwStatus.status -eq "unlocked") {
        Write-Host "Bitwarden is already unlocked." -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Running initial 'winix apply'..." -ForegroundColor Cyan
Write-Host ""

try {
    & $winixPath apply
}
catch {
    Write-Warning "Initial apply failed: $_"
    Write-Host "You can run 'winix apply' manually after resolving any issues." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Bootstrap complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Please restart PowerShell to use the 'winix' command." -ForegroundColor Cyan
Write-Host ""
Write-Host "Available commands:" -ForegroundColor DarkGray
Write-Host "  winix status         Show differences" -ForegroundColor DarkGray
Write-Host "  winix apply          Apply configuration" -ForegroundColor DarkGray
Write-Host "  winix --help         Show help" -ForegroundColor DarkGray
