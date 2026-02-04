<#
.SYNOPSIS
    winix - Declarative Environment Manager for Windows 11
.DESCRIPTION
    Manages packages, dotfiles, environment variables, and encrypted assets declaratively
#>

$ErrorActionPreference = 'Stop'

$WINIX_VERSION = "1.0.0"
$script:ScriptDir = $PSScriptRoot

# Import powershell-yaml module
Import-Module powershell-yaml -ErrorAction SilentlyContinue
if (-not (Get-Module powershell-yaml)) {
    Write-Error "powershell-yaml module is not installed. Run: Install-Module -Name powershell-yaml -Scope CurrentUser"
    exit 1
}

# Load library modules at script scope
. "$script:ScriptDir\lib\Common.ps1"
. "$script:ScriptDir\lib\Ui.ps1"
. "$script:ScriptDir\lib\State.ps1"
. "$script:ScriptDir\lib\Config.ps1"
. "$script:ScriptDir\lib\Packages.ps1"
. "$script:ScriptDir\lib\Winget.ps1"
. "$script:ScriptDir\lib\Dotfiles.ps1"
. "$script:ScriptDir\lib\Environment.ps1"
. "$script:ScriptDir\lib\Secrets.ps1"
. "$script:ScriptDir\lib\Tasks.ps1"

function _ShowHelp {
    Write-Host @"
winix - Declarative Environment Manager for Windows 11

Usage:
    winix apply                          Apply configuration
    winix status                         Show current state and differences
    winix --help                         Show this help
    winix --version                      Show version

    winix secret keygen [<path>]         Generate age key pair
    winix secret encrypt <file>          Encrypt file
    winix secret decrypt <file>          Decrypt file

    winix config encrypt [--remove]      Encrypt winix.yaml to winix.yaml.age
    winix config decrypt [--force]       Decrypt winix.yaml.age to winix.yaml
    winix config cache-clear             Clear decrypted config cache

Encrypted Config:
    winix supports encrypted config files (winix.yaml.age).
    Set one of these environment variables for decryption:
      - WINIX_AGE_KEY: The age secret key directly
      - WINIX_AGE_KEY_FILE: Path to file containing the age secret key
      - WINIX_BITWARDEN_ITEM: Bitwarden item name containing the age key
"@
}

function _ShowVersion {
    Write-Host "winix version $WINIX_VERSION"
}

function Invoke-WinixStatus {
    <#
    .SYNOPSIS
        Show differences between current environment and configuration
    #>
    Invoke-WinixApply -DryRun -BannerTitle "WINIX STATUS" -BannerSubtitle "Previewing changes (no changes will be made)."
}

function Invoke-WinixApply {
    <#
    .SYNOPSIS
        Apply configuration to the environment
    .PARAMETER DryRun
        If set, only show what would be done
    #>
    param(
        [switch]$DryRun,
        [string]$BannerTitle,
        [string]$BannerSubtitle
    )

    $configPath = Get-WinixConfigPath
    $config = Get-WinixConfig -ConfigPath $configPath
    $state = Get-WinixState

    $totalChanges = 0
    $hadErrors = $false

    if ($BannerTitle) {
        Write-UiBanner -Title $BannerTitle -Subtitle $BannerSubtitle
    }
    elseif ($DryRun) {
        Write-UiBanner -Title "WINIX APPLY (DRY RUN)" -Subtitle "No changes will be made."
    }
    else {
        Write-UiBanner -Title "WINIX APPLY" -Subtitle "Applying changes..."
    }

    # Scoop packages
    if ($config.packages -and ($config.packages.buckets -or $config.packages.apps)) {
        $diff = Get-PackageDiff -Config $config
        if ($diff.buckets.toAdd.Count -gt 0 -or
            $diff.buckets.toRemove.Count -gt 0 -or
            $diff.apps.toInstall.Count -gt 0 -or
            $diff.apps.toRemove.Count -gt 0 -or
            $diff.apps.toUpdate.Count -gt 0) {
            try {
                Write-SectionHeader -Title "Packages / Scoop"
                $result = Invoke-PackageApply -Config $config -DryRun:$DryRun
                $totalChanges += $result.changes
            }
            catch {
                $hadErrors = $true
                Write-Warning $_.Exception.Message
            }
        }
    }

    # Winget packages
    if ($config.packages -and $config.packages.winget -and $config.packages.winget.apps -and $config.packages.winget.apps.Count -gt 0) {
        $wingetDiff = Get-WingetPackageDiff -Config $config
        if ($wingetDiff.apps.toInstall.Count -gt 0 -or
            $wingetDiff.apps.toRemove.Count -gt 0 -or
            $wingetDiff.apps.toUpdate.Count -gt 0) {
            try {
                Write-SectionHeader -Title "Packages / Winget"
                $result = Invoke-WingetPackageApply -Config $config -DryRun:$DryRun
                $totalChanges += $result.changes
            }
            catch {
                $hadErrors = $true
                Write-Warning $_.Exception.Message
            }
        }
    }

    if ($config.environment) {
        $envDiff = Get-EnvironmentDiff -Config $config -State $state
        if ($envDiff.user.toAdd.Count -gt 0 -or
            $envDiff.user.toUpdate.Count -gt 0 -or
            $envDiff.user.toRemove.Count -gt 0 -or
            $envDiff.machine.toAdd.Count -gt 0 -or
            $envDiff.machine.toUpdate.Count -gt 0 -or
            $envDiff.machine.toRemove.Count -gt 0) {
            try {
                Write-SectionHeader -Title "Environment"
                $result = Invoke-EnvironmentApply -Config $config -State $state -DryRun:$DryRun
                $totalChanges += $result.changes
            }
            catch {
                $hadErrors = $true
                Write-Warning $_.Exception.Message
            }
        }

        $pathDiff = Get-PathDiff -Config $config -State $state
        $pathHasChanges = $false
        foreach ($scope in @("user", "machine")) {
            foreach ($position in @("prepend", "append")) {
                if ($pathDiff[$scope][$position].toAdd.Count -gt 0 -or
                    $pathDiff[$scope][$position].toRemove.Count -gt 0 -or
                    $pathDiff[$scope][$position].toTrack.Count -gt 0) {
                    $pathHasChanges = $true
                    break
                }
            }
            if ($pathHasChanges) { break }
        }
        if ($pathHasChanges) {
            try {
                Write-SectionHeader -Title "PATH"
                $result = Invoke-PathApply -Config $config -State $state -DryRun:$DryRun
                $totalChanges += $result.changes
            }
            catch {
                $hadErrors = $true
                Write-Warning $_.Exception.Message
            }
        }
    }

    if ($config.dotfiles) {
        $dotfilesDiff = Get-DotfilesDiff -Config $config -State $state
        $hasChanges = $dotfilesDiff.toAdd.Count -gt 0 -or
                      $dotfilesDiff.toUpdate.Count -gt 0 -or
                      $dotfilesDiff.toRemove.Count -gt 0 -or
                      $dotfilesDiff.toTrack.Count -gt 0

        if ($hasChanges) {
            try {
                Write-SectionHeader -Title "Dotfiles"
                $result = Invoke-DotfilesApply -Config $config -State $state -DryRun:$DryRun
                $totalChanges += $result.changes
            }
            catch {
                $hadErrors = $true
                Write-Warning $_.Exception.Message
            }
        }
    }

    if ($config.encrypted_files -and $config.encrypted_files.Count -gt 0) {
        $encryptedDiff = Get-EncryptedFilesDiff -Config $config -State $state
        if ($encryptedDiff.toAdd.Count -gt 0 -or
            $encryptedDiff.toUpdate.Count -gt 0 -or
            $encryptedDiff.toRemove.Count -gt 0) {
            try {
                Write-SectionHeader -Title "Encrypted Files"
                $result = Invoke-EncryptedFilesApply -Config $config -State $state -DryRun:$DryRun
                $totalChanges += $result.changes
            }
            catch {
                $hadErrors = $true
                Write-Warning $_.Exception.Message
            }
        }
    }

    if ($config.tasks -and $config.tasks.Count -gt 0) {
        $tasksDiff = Get-TasksDiff -Config $config -State $state
        $tasksHasChanges = $false
        foreach ($task in $tasksDiff.tasks) {
            if ($task.status.ToInstall.Count -gt 0 -or $task.status.ToRemove.Count -gt 0) {
                $tasksHasChanges = $true
                break
            }
        }
        if ($tasksHasChanges) {
            try {
                $result = Invoke-TasksApply -Config $config -State $state -DryRun:$DryRun
                $totalChanges += $result.changes
            }
            catch {
                $hadErrors = $true
                Write-Warning $_.Exception.Message
            }
        }
        elseif (-not $DryRun) {
            # Track UpToDate items in state (for initial state setup)
            foreach ($task in $tasksDiff.tasks) {
                $taskName = $task.name
                $taskConfig = $task.config
                if ($taskConfig.apps) {
                    foreach ($appId in $taskConfig.apps) {
                        Add-TaskItemToState -State $state -TaskName $taskName -Item $appId.ToString()
                    }
                }
            }
        }
    }

    if (-not $DryRun -and -not $hadErrors) {
        Save-WinixState -State $state
    }

    Write-Host ""
    if ($DryRun) {
        if ($totalChanges -gt 0) {
            Write-Host "Run 'winix apply' to apply changes." -ForegroundColor DarkGray
        }
        else {
            Write-Host "Everything is up to date." -ForegroundColor Green
        }
    }
    elseif ($totalChanges -gt 0) {
        Write-Host "Applied $totalChanges changes." -ForegroundColor Green
    }
    else {
        Write-Host "Everything is up to date." -ForegroundColor Green
    }
}

function Invoke-SecretCommand {
    <#
    .SYNOPSIS
        Handle secret management commands
    #>
    param(
        [array]$Arguments = @()
    )

    if (-not $Arguments -or $Arguments.Count -eq 0) {
        Write-Error "Missing secret subcommand. Run 'winix --help' for usage."
        exit 1
    }

    $configPath = Get-WinixConfigPath
    $config = Get-WinixConfig -ConfigPath $configPath

    $subcommand = $Arguments[0]
    $rest = @()
    if ($Arguments.Count -gt 1) {
        $rest = $Arguments[1..($Arguments.Count - 1)]
    }

    switch ($subcommand) {
        "keygen" {
            $outputPath = if ($rest.Count -gt 0) { $rest[0] } else { $null }
            New-AgeKeyPair -OutputPath $outputPath
        }
        "encrypt" {
            if ($rest.Count -eq 0) {
                Write-Error "Missing file path. Usage: winix secret encrypt <file>"
                exit 1
            }
            if (-not $config.age) {
                Write-Error "age section is not configured in winix.yaml"
                exit 1
            }
            Invoke-AgeEncrypt -FilePath $rest[0] -Config $config.age
        }
        "decrypt" {
            if ($rest.Count -eq 0) {
                Write-Error "Missing file path. Usage: winix secret decrypt <file>"
                exit 1
            }
            if (-not $config.age) {
                Write-Error "age section is not configured in winix.yaml"
                exit 1
            }
            $decrypted = Invoke-AgeDecrypt -FilePath $rest[0] -Config $config.age
            Write-Output $decrypted
        }
        default {
            Write-Error "Unknown secret command '$subcommand'. Run 'winix --help' for usage."
            exit 1
        }
    }
}

function Invoke-ConfigCommand {
    <#
    .SYNOPSIS
        Handle config management commands
    #>
    param(
        [array]$Arguments = @()
    )

    if (-not $Arguments -or $Arguments.Count -eq 0) {
        Write-Error "Missing config subcommand. Run 'winix --help' for usage."
        exit 1
    }

    $subcommand = $Arguments[0]
    $rest = @()
    if ($Arguments.Count -gt 1) {
        $rest = $Arguments[1..($Arguments.Count - 1)]
    }

    switch ($subcommand) {
        "encrypt" {
            $configPath = Get-WinixConfigPath
            if (-not (Test-Path $configPath)) {
                Write-Error "Configuration file not found: $configPath"
                exit 1
            }
            $removeOriginal = $rest -contains "--remove"
            Invoke-ConfigEncrypt -ConfigPath $configPath -RemoveOriginal:$removeOriginal
        }
        "decrypt" {
            $encryptedPath = Get-WinixConfigPath
            $encryptedPath = "$encryptedPath.age"
            if (-not (Test-Path $encryptedPath)) {
                Write-Error "Encrypted config file not found: $encryptedPath"
                exit 1
            }
            $force = $rest -contains "--force"
            Invoke-ConfigDecrypt -EncryptedPath $encryptedPath -Force:$force
        }
        "cache-clear" {
            Clear-ConfigCache
        }
        default {
            Write-Error "Unknown config command '$subcommand'. Run 'winix --help' for usage."
            exit 1
        }
    }
}

function Main {
    param(
        [array]$Arguments
    )

    if ($Arguments.Count -eq 0) {
        _ShowHelp
        return
    }

    $command = $Arguments[0]
    $rest = @()
    if ($Arguments.Count -gt 1) {
        $rest = $Arguments[1..($Arguments.Count - 1)]
    }

    switch ($command) {
        "--help" {
            _ShowHelp
        }
        "-h" {
            _ShowHelp
        }
        "--version" {
            _ShowVersion
        }
        "-v" {
            _ShowVersion
        }
        "status" {
            Invoke-WinixStatus
        }
        "apply" {
            if ($rest -contains "--dry-run") {
                Write-Error "The --dry-run option has been removed. Use 'winix status' for previews."
                exit 1
            }
            Invoke-WinixApply
        }
        "secret" {
            Invoke-SecretCommand -Arguments $rest
        }
        "config" {
            Invoke-ConfigCommand -Arguments $rest
        }
        default {
            Write-Error "Unknown command '$command'. Run 'winix --help' for usage."
            exit 1
        }
    }
}

Main -Arguments $args
