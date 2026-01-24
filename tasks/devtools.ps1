<#
.SYNOPSIS
    Development tools installation task for winix
.DESCRIPTION
    Runs mise install and mise run setup
#>

$ErrorActionPreference = 'Stop'

function global:Get-TaskInfo {
    <#
    .SYNOPSIS
        Returns task information
    #>
    return @{
        Name        = "Dev Tools"
        Description = "Install mise tools and run setup task"
        Version     = "2.0.0"
    }
}

function global:_CommandExists {
    <#
    .SYNOPSIS
        Check if a command exists
    .PARAMETER Command
        Command name to check
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function global:_GetMiseMissingTools {
    <#
    .SYNOPSIS
        Get list of missing mise tools
    #>
    if (-not (_CommandExists "mise")) {
        return @()
    }

    try {
        $output = mise list --missing 2>&1
        if ($LASTEXITCODE -ne 0) {
            return @()
        }

        $missing = @()
        foreach ($line in $output) {
            $line = $line.ToString().Trim()
            if ($line -and $line -notmatch "^(No |missing)") {
                $missing += $line
            }
        }
        return $missing
    }
    catch {
        return @()
    }
}

function global:_HasMiseSetupTask {
    <#
    .SYNOPSIS
        Check if mise has a setup task defined
    #>
    if (-not (_CommandExists "mise")) {
        return $false
    }

    try {
        $output = mise tasks 2>&1
        if ($LASTEXITCODE -ne 0) {
            return $false
        }

        foreach ($line in $output) {
            if ($line -match '^\s*setup\s') {
                return $true
            }
        }
        return $false
    }
    catch {
        return $false
    }
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
        [hashtable]$TaskState = @{}
    )

    $status = @{
        ToInstall = @()
        ToRemove  = @()
        UpToDate  = @()
    }

    if ($Config.mise) {
        if (-not (_CommandExists "mise")) {
            $status.ToInstall += "mise (not installed)"
        }
        else {
            $missing = _GetMiseMissingTools
            if ($missing.Count -gt 0) {
                foreach ($tool in $missing) {
                    $status.ToInstall += "mise: $tool"
                }
            }
            else {
                $status.UpToDate += "mise: all tools installed"
            }

            # Check for setup task
            if (_HasMiseSetupTask) {
                $status.UpToDate += "mise: setup task available"
            }
        }
    }

    return $status
}

function global:Invoke-TaskApply {
    <#
    .SYNOPSIS
        Install mise tools and run setup task
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
        [hashtable]$TaskState = @{},
        [switch]$DryRun
    )

    $result = @{
        installed = @()
        removed   = @()
    }

    if ($Config.mise) {
        if (-not (_CommandExists "mise")) {
            Write-Warning "mise is not installed, skipping"
            return $result
        }

        # Run mise install
        $missing = _GetMiseMissingTools
        if ($missing.Count -gt 0) {
            Write-Host "    Running mise install..." -ForegroundColor DarkGray
            if (-not $DryRun) {
                mise install
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "    mise install completed" -ForegroundColor Green
                }
                else {
                    Write-Error "mise install failed"
                }
            }
        }

        # Run mise run setup if task exists
        if (_HasMiseSetupTask) {
            Write-Host "    Running mise run setup..." -ForegroundColor DarkGray
            if (-not $DryRun) {
                mise run setup
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "    mise run setup completed" -ForegroundColor Green
                }
                else {
                    Write-Error "mise run setup failed"
                }
            }
        }
    }

    return $result
}

function global:Invoke-TaskCleanup {
    <#
    .SYNOPSIS
        Clean up task-specific helper functions
    #>
    Remove-Item -Path "Function:\_CommandExists" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetMiseMissingTools" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_HasMiseSetupTask" -ErrorAction SilentlyContinue
}
