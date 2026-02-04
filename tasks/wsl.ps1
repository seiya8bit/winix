<#
.SYNOPSIS
    WSL installation task for winix
.DESCRIPTION
    Installs WSL (Windows Subsystem for Linux)
#>

$ErrorActionPreference = 'Stop'

function global:Get-TaskInfo {
    <#
    .SYNOPSIS
        Returns task information
    #>
    return @{
        Name        = "WSL"
        Description = "Install WSL"
        Version     = "3.0.0"
    }
}

function global:_IsWslInstalled {
    <#
    .SYNOPSIS
        Check if WSL is installed
    .DESCRIPTION
        Windows 11 ships with a wsl.exe stub in System32 even when WSL is not installed.
        Use 'wsl --version' to verify WSL is actually functional.
    #>
    $wsl = Get-Command wsl -ErrorAction SilentlyContinue
    if ($null -eq $wsl) {
        return $false
    }
    # wsl.exe stub exists on Windows 11 without WSL installed.
    # 'wsl --version' returns exit code 0 only when WSL is properly installed.
    $null = wsl --version 2>&1
    return $LASTEXITCODE -eq 0
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

    $stateItems = @()
    if ($TaskState.items) {
        $stateItems = @($TaskState.items)
    }

    # Check WSL installation
    if ($Config.wsl) {
        # First check if already recorded in state (from previous apply)
        $inState = $stateItems -contains "WSL"
        if ($inState) {
            $status.UpToDate += "WSL"
        }
        elseif (_IsWslInstalled) {
            # Installed but not in state, need to track
            $status.ToInstall += "WSL (track existing)"
        }
        else {
            $status.ToInstall += "WSL"
        }
    }

    return $status
}

function global:Invoke-TaskApply {
    <#
    .SYNOPSIS
        Install WSL
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

    $stateItems = @()
    if ($TaskState.items) {
        $stateItems = @($TaskState.items)
    }

    $needsReboot = $false

    # Install WSL
    if ($Config.wsl) {
        # Check if already recorded in state
        $inState = $stateItems -contains "WSL"
        if (-not $inState) {
            if (_IsWslInstalled) {
                # Already installed, just record in state
                $result.installed += "WSL"
            }
            else {
                Write-Host "    Installing WSL..." -ForegroundColor DarkGray

                if (-not $DryRun) {
                    try {
                        wsl --install --no-launch
                        if ($LASTEXITCODE -eq 0) {
                            $result.installed += "WSL"
                            $needsReboot = $true
                            Write-Host "    WSL installed" -ForegroundColor Green
                        }
                        else {
                            Write-Error "Failed to install WSL"
                        }
                    }
                    catch {
                        Write-Error "Failed to install WSL: $_"
                    }
                }
            }
        }
    }

    if ($needsReboot) {
        Write-Host ""
        Write-Host "    NOTICE: A system restart is required to complete the installation." -ForegroundColor Yellow
    }

    return $result
}

function global:Invoke-TaskCleanup {
    <#
    .SYNOPSIS
        Clean up task-specific helper functions
    #>
    Remove-Item -Path "Function:\_IsWslInstalled" -ErrorAction SilentlyContinue
}
