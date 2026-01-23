<#
.SYNOPSIS
    Development tools installation task for winix
.DESCRIPTION
    Runs mise install and installs uv tools
#>

$ErrorActionPreference = 'Stop'

function global:Get-TaskInfo {
    <#
    .SYNOPSIS
        Returns task information
    #>
    return @{
        Name        = "Dev Tools"
        Description = "Install mise tools and uv tools"
        Version     = "1.0.0"
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

function global:_GetInstalledUvTools {
    <#
    .SYNOPSIS
        Get list of installed uv tools
    #>
    if (-not (_CommandExists "uv")) {
        return @()
    }

    try {
        # Prefer structured output if supported, fallback to text parsing.
        $jsonOutput = & uv tool list --format json 2>$null
        if ($LASTEXITCODE -eq 0 -and $jsonOutput) {
            try {
                $parsed = $jsonOutput | ConvertFrom-Json
                if ($parsed) {
                    $tools = @()
                    foreach ($item in $parsed) {
                        if ($item.name) {
                            $tools += $item.name
                        }
                    }
                    if ($tools.Count -gt 0) {
                        return $tools
                    }
                }
            }
            catch {
                # Fall through to text parsing.
            }
        }

        $output = uv tool list 2>&1
        if ($LASTEXITCODE -ne 0) {
            return @()
        }

        $tools = @()
        foreach ($line in $output) {
            $line = $line.ToString().Trim()
            # Format: "toolname v1.2.3" or "toolname v1.2.3 [extra1, extra2]"
            if ($line -match '^(\S+)\s+v[\d.]+') {
                $tools += $Matches[1]
            }
        }
        return $tools
    }
    catch {
        return @()
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

    # Check mise (not tracked in state - mise manages its own state)
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
        }
    }

    # Check uv tools (tracked in state.json)
    $configUvTools = @()
    if ($Config.uv_tools) {
        $configUvTools = @($Config.uv_tools | ForEach-Object { $_.name })

        if (-not (_CommandExists "uv")) {
            $status.ToInstall += "uv (not installed)"
        }
        else {
            $installedTools = _GetInstalledUvTools

            foreach ($tool in $Config.uv_tools) {
                $toolName = $tool.name
                $extras = @()
                if ($tool.extras) {
                    $extras = @($tool.extras)
                }

                $displayName = if ($extras.Count -gt 0) {
                    "uv: $toolName (with $($extras -join ', '))"
                }
                else {
                    "uv: $toolName"
                }

                $isInstalled = $toolName -in $installedTools
                $isInState = $toolName -in $stateItems

                if ($isInstalled -and $isInState) {
                    $status.UpToDate += $displayName
                }
                elseif ($isInstalled -and -not $isInState) {
                    # Installed but not in state - need to register
                    $status.ToInstall += "$displayName (register to state)"
                }
                else {
                    $status.ToInstall += $displayName
                }
            }
        }
    }

    # Check for uv tools in state but not in config (ToRemove)
    foreach ($item in $stateItems) {
        if ($item -notin $configUvTools) {
            $status.ToRemove += "uv: $item"
        }
    }

    return $status
}

function global:Invoke-TaskApply {
    <#
    .SYNOPSIS
        Install mise tools and uv tools
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

    # Run mise install (not tracked in state - mise manages its own state)
    if ($Config.mise) {
        if (-not (_CommandExists "mise")) {
            Write-Warning "mise is not installed, skipping"
        }
        else {
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
        }
    }

    # Install uv tools (tracked in state.json)
    $configUvTools = @()
    if ($Config.uv_tools) {
        $configUvTools = @($Config.uv_tools | ForEach-Object { $_.name })

        if (-not (_CommandExists "uv")) {
            Write-Warning "uv is not installed, skipping"
        }
        else {
            $installedTools = _GetInstalledUvTools

            foreach ($tool in $Config.uv_tools) {
                $toolName = $tool.name
                $extras = @()
                if ($tool.extras) {
                    $extras = @($tool.extras)
                }

                # Already installed - just track in state
                if ($toolName -in $installedTools) {
                    $result.installed += $toolName
                    continue
                }

                # Build command arguments
                $uvArgs = @("tool", "install", $toolName)
                foreach ($extra in $extras) {
                    $uvArgs += "--with"
                    $uvArgs += $extra
                }

                $displayCmd = "uv $($uvArgs -join ' ')"
                Write-Host "    Running: $displayCmd" -ForegroundColor DarkGray

                if (-not $DryRun) {
                    & uv @uvArgs
                    if ($LASTEXITCODE -eq 0) {
                        $result.installed += $toolName
                        Write-Host "    Installed: $toolName" -ForegroundColor Green
                    }
                    else {
                        Write-Error "Failed to install $toolName"
                    }
                }
            }
        }
    }

    # Uninstall uv tools removed from config
    if (_CommandExists "uv") {
        foreach ($item in $stateItems) {
            if ($item -notin $configUvTools) {
                Write-Host "    Running: uv tool uninstall $item" -ForegroundColor DarkGray

                if (-not $DryRun) {
                    & uv tool uninstall $item
                    if ($LASTEXITCODE -eq 0) {
                        $result.removed += $item
                        Write-Host "    Uninstalled: $item" -ForegroundColor Green
                    }
                    else {
                        Write-Warning "Failed to uninstall $item"
                    }
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
    Remove-Item -Path "Function:\_GetInstalledUvTools" -ErrorAction SilentlyContinue
}
