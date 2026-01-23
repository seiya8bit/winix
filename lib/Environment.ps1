<#
.SYNOPSIS
    Environment variable management module for winix
.DESCRIPTION
    Manages user and machine level environment variables and PATH with full sync support
#>

$ErrorActionPreference = 'Stop'

function _GetRegistryEnvValue {
    <#
    .SYNOPSIS
        Get environment variable value from registry
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [ValidateSet("user", "machine")]
        [string]$Scope
    )

    $regPath = if ($Scope -eq "user") {
        "HKCU:\Environment"
    }
    else {
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
    }

    try {
        $value = Get-ItemPropertyValue -Path $regPath -Name $Name -ErrorAction SilentlyContinue
        return $value
    }
    catch {
        return $null
    }
}

function _SetRegistryEnvValue {
    <#
    .SYNOPSIS
        Set environment variable value in registry
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [Parameter(Mandatory = $true)]
        [ValidateSet("user", "machine")]
        [string]$Scope
    )

    if ($Scope -eq "machine") {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
        gsudo powershell -Command "Set-ItemProperty -Path '$regPath' -Name '$Name' -Value '$Value'"
    }
    else {
        $regPath = "HKCU:\Environment"
        Set-ItemProperty -Path $regPath -Name $Name -Value $Value
    }

    _BroadcastSettingChange
}

function _RemoveRegistryEnvValue {
    <#
    .SYNOPSIS
        Remove environment variable from registry
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [ValidateSet("user", "machine")]
        [string]$Scope
    )

    if ($Scope -eq "machine") {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
        gsudo powershell -Command "Remove-ItemProperty -Path '$regPath' -Name '$Name' -ErrorAction SilentlyContinue"
    }
    else {
        $regPath = "HKCU:\Environment"
        Remove-ItemProperty -Path $regPath -Name $Name -ErrorAction SilentlyContinue
    }

    _BroadcastSettingChange
}

function _GetRegistryPath {
    <#
    .SYNOPSIS
        Get PATH value from registry
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("user", "machine")]
        [string]$Scope
    )

    return _GetRegistryEnvValue -Name "Path" -Scope $Scope
}

function _SetRegistryPath {
    <#
    .SYNOPSIS
        Set PATH value in registry
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [Parameter(Mandatory = $true)]
        [ValidateSet("user", "machine")]
        [string]$Scope
    )

    if ($Scope -eq "machine") {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
        $escapedValue = $Value -replace "'", "''"
        gsudo powershell -Command "Set-ItemProperty -Path '$regPath' -Name 'Path' -Value '$escapedValue' -Type ExpandString"
    }
    else {
        $regPath = "HKCU:\Environment"
        Set-ItemProperty -Path $regPath -Name "Path" -Value $Value -Type ExpandString
    }

    _BroadcastSettingChange
}

function _BroadcastSettingChange {
    <#
    .SYNOPSIS
        Broadcast WM_SETTINGCHANGE to notify other processes of environment changes
    #>
    $signature = @"
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
"@

    try {
        $type = Add-Type -MemberDefinition $signature -Name "WinAPI" -Namespace "BroadcastSetting" -PassThru -ErrorAction SilentlyContinue
        $HWND_BROADCAST = [IntPtr]0xffff
        $WM_SETTINGCHANGE = 0x1a
        $SMTO_ABORTIFHUNG = 0x0002
        $result = [UIntPtr]::Zero
        $type::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, "Environment", $SMTO_ABORTIFHUNG, 5000, [ref]$result) | Out-Null
    }
    catch {
    }
}

function _ExpandPathVariables {
    <#
    .SYNOPSIS
        Expand shell variables and tilde to Windows environment variable format
    .DESCRIPTION
        Converts shell-style variables to Windows %VAR% format:
        - ~ → %USERPROFILE%
        - $HOME → %USERPROFILE%
        - $env:VARNAME → %VARNAME%
        - $VARNAME → %VARNAME% (if VARNAME is a known env var)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # Replace tilde at start with %USERPROFILE%
    if ($Path -match '^~[\\/]?') {
        $Path = $Path -replace '^~', '%USERPROFILE%'
    }

    # Replace $HOME with %USERPROFILE%
    $Path = $Path -replace '\$HOME\b', '%USERPROFILE%'

    # Replace $env:VARNAME with %VARNAME% (generic pattern)
    $Path = $Path -replace '\$env:(\w+)', '%$1%'

    # Replace $VARNAME with %VARNAME% for common environment variables
    $commonEnvVars = @(
        'USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP',
        'ProgramFiles', 'ProgramData', 'SystemRoot', 'HOMEDRIVE', 'HOMEPATH'
    )
    foreach ($var in $commonEnvVars) {
        $Path = $Path -replace "\`$$var\b", "%$var%"
    }

    return $Path
}

function _ParsePathString {
    <#
    .SYNOPSIS
        Parse PATH string into array of paths
    #>
    param(
        [string]$PathString
    )

    if ([string]::IsNullOrWhiteSpace($PathString)) {
        return @()
    }

    return @($PathString -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function _JoinPathArray {
    <#
    .SYNOPSIS
        Join array of paths into PATH string
    #>
    param(
        [array]$Paths
    )

    return ($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ';'
}

function _PathContains {
    <#
    .SYNOPSIS
        Check if PATH array contains a specific path (case-insensitive)
    #>
    param(
        [array]$PathArray,
        [string]$PathToFind
    )

    # First convert shell syntax to Windows env var syntax, then expand
    $normalizedFind = _ExpandPathVariables -Path $PathToFind
    $expandedFind = [Environment]::ExpandEnvironmentVariables($normalizedFind)

    foreach ($p in $PathArray) {
        $normalizedP = _ExpandPathVariables -Path $p
        $expandedP = [Environment]::ExpandEnvironmentVariables($normalizedP)
        if ($expandedP -eq $expandedFind) {
            return $true
        }
    }
    return $false
}

function Get-EnvironmentDiff {
    <#
    .SYNOPSIS
        Calculate differences for environment variables
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
        user = @{
            toAdd = @()
            toUpdate = @()
            toRemove = @()
        }
        machine = @{
            toAdd = @()
            toUpdate = @()
            toRemove = @()
        }
    }

    foreach ($scope in @("user", "machine")) {
        $configVars = $Config.environment[$scope]
        $stateVars = $State.environment[$scope]

        foreach ($name in $configVars.Keys) {
            $configValue = $configVars[$name]
            $currentValue = _GetRegistryEnvValue -Name $name -Scope $scope

            if ($null -eq $currentValue) {
                $diff[$scope].toAdd += @{ name = $name; value = $configValue }
            }
            elseif ($currentValue -ne $configValue) {
                $diff[$scope].toUpdate += @{ name = $name; value = $configValue; oldValue = $currentValue }
            }
        }

        $configNames = @($configVars.Keys)
        foreach ($name in $stateVars) {
            if ($name -notin $configNames) {
                $diff[$scope].toRemove += $name
            }
        }
    }

    return $diff
}

function Get-PathDiff {
    <#
    .SYNOPSIS
        Calculate differences for PATH
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
        user = @{
            prepend = @{ toAdd = @(); toRemove = @(); toTrack = @() }
            append = @{ toAdd = @(); toRemove = @(); toTrack = @() }
        }
        machine = @{
            prepend = @{ toAdd = @(); toRemove = @(); toTrack = @() }
            append = @{ toAdd = @(); toRemove = @(); toTrack = @() }
        }
    }

    foreach ($scope in @("user", "machine")) {
        $currentPath = _GetRegistryPath -Scope $scope
        $currentPaths = _ParsePathString $currentPath

        foreach ($position in @("prepend", "append")) {
            $configPaths = $Config.environment.path[$scope][$position]
            $statePaths = $State.path[$scope][$position]

            foreach ($path in $configPaths) {
                $inCurrent = _PathContains -PathArray $currentPaths -PathToFind $path
                $inState = $path -in $statePaths

                if (-not $inCurrent) {
                    $diff[$scope][$position].toAdd += $path
                }
                elseif (-not $inState) {
                    $diff[$scope][$position].toTrack += $path
                }
            }

            foreach ($path in $statePaths) {
                if ($path -notin $configPaths) {
                    $diff[$scope][$position].toRemove += $path
                }
            }
        }
    }

    return $diff
}

function Invoke-EnvironmentApply {
    <#
    .SYNOPSIS
        Apply environment variable changes
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

    $diff = Get-EnvironmentDiff -Config $Config -State $State
    $changes = 0

    $needsMachine = $diff.machine.toAdd.Count -gt 0 -or
                    $diff.machine.toUpdate.Count -gt 0 -or
                    $diff.machine.toRemove.Count -gt 0 -or
                    $State.environment.machine.Count -gt 0

    if ($needsMachine -and -not $DryRun) {
        Assert-GsudoInstalled
    }

    foreach ($scope in @("user", "machine")) {
        foreach ($name in $diff[$scope].toRemove) {
            if ($DryRun) {
                Write-Host "  - $name" -ForegroundColor Red -NoNewline
                Write-Host "    (would remove, $scope)" -ForegroundColor DarkGray
            }
            else {
                Write-Host "  - $name" -ForegroundColor Red -NoNewline
                try {
                    _RemoveRegistryEnvValue -Name $name -Scope $scope
                    Remove-EnvironmentFromState -State $State -Name $name -Scope $scope
                    Write-Host "    done" -ForegroundColor DarkGray
                }
                catch {
                    Write-Host "    failed" -ForegroundColor Red
                    throw
                }
            }
            $changes++
        }

        foreach ($item in $diff[$scope].toAdd) {
            if ($DryRun) {
                Write-Host "  + $($item.name)=$($item.value)" -ForegroundColor Green -NoNewline
                Write-Host "    (would add, $scope)" -ForegroundColor DarkGray
            }
            else {
                Write-Host "  + $($item.name)=$($item.value)" -ForegroundColor Green -NoNewline
                try {
                    _SetRegistryEnvValue -Name $item.name -Value $item.value -Scope $scope
                    Add-EnvironmentToState -State $State -Name $item.name -Scope $scope
                    Write-Host "    done" -ForegroundColor DarkGray
                }
                catch {
                    Write-Host "    failed" -ForegroundColor Red
                    throw
                }
            }
            $changes++
        }

        foreach ($item in $diff[$scope].toUpdate) {
            if ($DryRun) {
                Write-Host "  ~ $($item.name)=$($item.value)" -ForegroundColor Yellow -NoNewline
                Write-Host "    (would update, $scope)" -ForegroundColor DarkGray
            }
            else {
                Write-Host "  ~ $($item.name)=$($item.value)" -ForegroundColor Yellow -NoNewline
                try {
                    _SetRegistryEnvValue -Name $item.name -Value $item.value -Scope $scope
                    Add-EnvironmentToState -State $State -Name $item.name -Scope $scope
                    Write-Host "    done" -ForegroundColor DarkGray
                }
                catch {
                    Write-Host "    failed" -ForegroundColor Red
                    throw
                }
            }
            $changes++
        }
    }

    return @{ changes = $changes }
}

function Invoke-PathApply {
    <#
    .SYNOPSIS
        Apply PATH changes
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

    $diff = Get-PathDiff -Config $Config -State $State
    $changes = 0

    $needsMachine = $diff.machine.prepend.toAdd.Count -gt 0 -or
                    $diff.machine.prepend.toRemove.Count -gt 0 -or
                    $diff.machine.append.toAdd.Count -gt 0 -or
                    $diff.machine.append.toRemove.Count -gt 0 -or
                    $State.path.machine.prepend.Count -gt 0 -or
                    $State.path.machine.append.Count -gt 0

    if ($needsMachine -and -not $DryRun) {
        Assert-GsudoInstalled
    }

    foreach ($scope in @("user", "machine")) {
        $currentPath = _GetRegistryPath -Scope $scope
        $currentPaths = _ParsePathString $currentPath
        $modified = $false

        foreach ($path in $diff[$scope].prepend.toRemove) {
            $normalizedPath = _ExpandPathVariables -Path $path
            if ($DryRun) {
                Write-Host "  - PATH: $normalizedPath" -ForegroundColor Red -NoNewline
                Write-Host "    (would remove, $scope prepend)" -ForegroundColor DarkGray
            }
            else {
                Write-Host "  - PATH: $normalizedPath" -ForegroundColor Red -NoNewline
                $expandedPath = [Environment]::ExpandEnvironmentVariables($normalizedPath)
                $currentPaths = @($currentPaths | Where-Object {
                    $normalizedP = _ExpandPathVariables -Path $_
                    [Environment]::ExpandEnvironmentVariables($normalizedP) -ne $expandedPath
                })
                Remove-PathFromState -State $State -Path $path -Scope $scope -Position "prepend"
                $modified = $true
                Write-Host "    done" -ForegroundColor DarkGray
            }
            $changes++
        }

        foreach ($path in $diff[$scope].append.toRemove) {
            $normalizedPath = _ExpandPathVariables -Path $path
            if ($DryRun) {
                Write-Host "  - PATH: $normalizedPath" -ForegroundColor Red -NoNewline
                Write-Host "    (would remove, $scope append)" -ForegroundColor DarkGray
            }
            else {
                Write-Host "  - PATH: $normalizedPath" -ForegroundColor Red -NoNewline
                $expandedPath = [Environment]::ExpandEnvironmentVariables($normalizedPath)
                $currentPaths = @($currentPaths | Where-Object {
                    $normalizedP = _ExpandPathVariables -Path $_
                    [Environment]::ExpandEnvironmentVariables($normalizedP) -ne $expandedPath
                })
                Remove-PathFromState -State $State -Path $path -Scope $scope -Position "append"
                $modified = $true
                Write-Host "    done" -ForegroundColor DarkGray
            }
            $changes++
        }

        foreach ($path in $diff[$scope].prepend.toAdd) {
            $expandedPath = _ExpandPathVariables -Path $path
            if ($DryRun) {
                Write-Host "  + PATH: $expandedPath" -ForegroundColor Green -NoNewline
                Write-Host "    (would prepend, $scope)" -ForegroundColor DarkGray
            }
            else {
                Write-Host "  + PATH: $expandedPath" -ForegroundColor Green -NoNewline
                $currentPaths = @($expandedPath) + $currentPaths
                Add-PathToState -State $State -Path $path -Scope $scope -Position "prepend"
                $modified = $true
                Write-Host "    done" -ForegroundColor DarkGray
            }
            $changes++
        }

        foreach ($path in $diff[$scope].append.toAdd) {
            $expandedPath = _ExpandPathVariables -Path $path
            if ($DryRun) {
                Write-Host "  + PATH: $expandedPath" -ForegroundColor Green -NoNewline
                Write-Host "    (would append, $scope)" -ForegroundColor DarkGray
            }
            else {
                Write-Host "  + PATH: $expandedPath" -ForegroundColor Green -NoNewline
                $currentPaths = $currentPaths + @($expandedPath)
                Add-PathToState -State $State -Path $path -Scope $scope -Position "append"
                $modified = $true
                Write-Host "    done" -ForegroundColor DarkGray
            }
            $changes++
        }

        foreach ($path in $diff[$scope].prepend.toTrack) {
            $displayPath = _ExpandPathVariables -Path $path
            if ($DryRun) {
                Write-Host "  = PATH: $displayPath" -ForegroundColor Yellow -NoNewline
                Write-Host "    (would start tracking, $scope prepend)" -ForegroundColor DarkGray
            }
            else {
                Write-Host "  = PATH: $displayPath" -ForegroundColor Yellow -NoNewline
                Add-PathToState -State $State -Path $path -Scope $scope -Position "prepend"
                Write-Host "    done" -ForegroundColor DarkGray
            }
            $changes++
        }

        foreach ($path in $diff[$scope].append.toTrack) {
            $displayPath = _ExpandPathVariables -Path $path
            if ($DryRun) {
                Write-Host "  = PATH: $displayPath" -ForegroundColor Yellow -NoNewline
                Write-Host "    (would start tracking, $scope append)" -ForegroundColor DarkGray
            }
            else {
                Write-Host "  = PATH: $displayPath" -ForegroundColor Yellow -NoNewline
                Add-PathToState -State $State -Path $path -Scope $scope -Position "append"
                Write-Host "    done" -ForegroundColor DarkGray
            }
            $changes++
        }

        if ($modified -and -not $DryRun) {
            $newPath = _JoinPathArray $currentPaths
            _SetRegistryPath -Value $newPath -Scope $scope
        }
    }

    return @{ changes = $changes }
}

function Show-EnvironmentStatus {
    <#
    .SYNOPSIS
        Show environment variable status differences
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

    $diff = Get-EnvironmentDiff -Config $Config -State $State

    $hasChanges = $false
    foreach ($scope in @("user", "machine")) {
        if ($diff[$scope].toAdd.Count -gt 0 -or
            $diff[$scope].toUpdate.Count -gt 0 -or
            $diff[$scope].toRemove.Count -gt 0) {
            $hasChanges = $true
            break
        }
    }

    if (-not $hasChanges) {
        return
    }

    Write-SectionHeader -Title "Environment"

    foreach ($scope in @("user", "machine")) {
        foreach ($item in $diff[$scope].toAdd) {
            Write-Host "  + $($item.name)=$($item.value)" -ForegroundColor Green -NoNewline
            Write-Host "    ($scope)" -ForegroundColor DarkGray
        }

        foreach ($item in $diff[$scope].toUpdate) {
            Write-Host "  ~ $($item.name)=$($item.value)" -ForegroundColor Yellow -NoNewline
            Write-Host "    ($scope)" -ForegroundColor DarkGray
        }

        foreach ($name in $diff[$scope].toRemove) {
            Write-Host "  - $name" -ForegroundColor Red -NoNewline
            Write-Host "    ($scope)" -ForegroundColor DarkGray
        }
    }
}

function Show-PathStatus {
    <#
    .SYNOPSIS
        Show PATH status differences
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

    $diff = Get-PathDiff -Config $Config -State $State

    $hasChanges = $false
    foreach ($scope in @("user", "machine")) {
        foreach ($position in @("prepend", "append")) {
            if ($diff[$scope][$position].toAdd.Count -gt 0 -or
                $diff[$scope][$position].toRemove.Count -gt 0 -or
                $diff[$scope][$position].toTrack.Count -gt 0) {
                $hasChanges = $true
                break
            }
        }
        if ($hasChanges) { break }
    }

    if (-not $hasChanges) {
        return
    }

    Write-SectionHeader -Title "PATH"

    foreach ($scope in @("user", "machine")) {
        foreach ($position in @("prepend", "append")) {
            foreach ($path in $diff[$scope][$position].toAdd) {
                $displayPath = _ExpandPathVariables -Path $path
                Write-Host "  + $displayPath" -ForegroundColor Green -NoNewline
                Write-Host "    ($scope $position)" -ForegroundColor DarkGray
            }

            foreach ($path in $diff[$scope][$position].toRemove) {
                $displayPath = _ExpandPathVariables -Path $path
                Write-Host "  - $displayPath" -ForegroundColor Red -NoNewline
                Write-Host "    ($scope $position)" -ForegroundColor DarkGray
            }

            foreach ($path in $diff[$scope][$position].toTrack) {
                $displayPath = _ExpandPathVariables -Path $path
                Write-Host "  = $displayPath" -ForegroundColor Yellow -NoNewline
                Write-Host "    ($scope $position, start tracking)" -ForegroundColor DarkGray
            }
        }
    }
}

