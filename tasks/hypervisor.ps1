<#
.SYNOPSIS
    Hypervisor and WSL installation task for winix
.DESCRIPTION
    Configures hypervisor launch type and installs WSL
#>

$ErrorActionPreference = 'Stop'

function global:Get-TaskInfo {
    <#
    .SYNOPSIS
        Returns task information
    #>
    return @{
        Name        = "Hypervisor"
        Description = "Configure hypervisor and install WSL"
        Version     = "2.0.0"
    }
}

function global:_EnsureGsudo {
    <#
    .SYNOPSIS
        Ensure gsudo is installed
    #>
    $gsudo = Get-Command gsudo -ErrorAction SilentlyContinue
    if ($null -eq $gsudo) {
        throw "gsudo is required for hypervisor configuration. Install it via Scoop: scoop install gsudo"
    }
}

function global:_GetHypervisorLaunchType {
    <#
    .SYNOPSIS
        Get current hypervisor launch type from BCD
    #>
    try {
        $bcdOutput = bcdedit /enum 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            return "Unknown"
        }
        if ($bcdOutput -match "hypervisorlaunchtype\s+(\w+)") {
            return $Matches[1]
        }
        return "Off"
    }
    catch {
        return "Unknown"
    }
}

function global:_IsWslInstalled {
    <#
    .SYNOPSIS
        Check if WSL is installed
    #>
    return $null -ne (Get-Command wsl -ErrorAction SilentlyContinue)
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

    # Check hypervisor launch type
    if ($Config.hypervisor) {
        # First check if already recorded in state (from previous apply)
        $inState = $stateItems -contains "hypervisorlaunchtype"
        if ($inState) {
            $status.UpToDate += "hypervisorlaunchtype: Auto"
        }
        else {
            # Try to read actual value (requires admin)
            $launchType = _GetHypervisorLaunchType
            if ($launchType -eq "Auto") {
                $status.UpToDate += "hypervisorlaunchtype: Auto"
            }
            elseif ($launchType -eq "Unknown") {
                $status.ToInstall += "hypervisorlaunchtype (requires admin)"
            }
            else {
                $status.ToInstall += "hypervisorlaunchtype: $launchType -> Auto"
            }
        }
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
        Configure hypervisor and install WSL
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

    # Configure hypervisor launch type
    if ($Config.hypervisor) {
        # Check if already recorded in state
        $inState = $stateItems -contains "hypervisorlaunchtype"
        if (-not $inState) {
            _EnsureGsudo
            # Use gsudo to check actual value
            $bcdOutput = gsudo bcdedit /enum 2>&1 | Out-String
            $launchType = if ($bcdOutput -match "hypervisorlaunchtype\s+(\w+)") { $Matches[1] } else { "Off" }

            if ($launchType -ne "Auto") {
                Write-Host "    Setting hypervisorlaunchtype to Auto..." -ForegroundColor DarkGray

                if (-not $DryRun) {
                    try {
                        gsudo bcdedit /set hypervisorlaunchtype auto | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            $result.installed += "hypervisorlaunchtype"
                            $needsReboot = $true
                            Write-Host "    hypervisorlaunchtype set to Auto" -ForegroundColor Green
                        }
                        else {
                            Write-Error "Failed to set hypervisorlaunchtype"
                        }
                    }
                    catch {
                        Write-Error "Failed to set hypervisorlaunchtype: $_"
                    }
                }
            }
            else {
                # Already Auto, just record in state
                $result.installed += "hypervisorlaunchtype"
            }
        }
    }

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
    Remove-Item -Path "Function:\_EnsureGsudo" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetHypervisorLaunchType" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_IsWslInstalled" -ErrorAction SilentlyContinue
}
