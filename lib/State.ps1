<#
.SYNOPSIS
    State management module for winix
.DESCRIPTION
    Manages state.json file for tracking winix-managed items
#>

$ErrorActionPreference = 'Stop'

$STATE_FILE_PATH = Join-Path $env:USERPROFILE ".config\winix\state.json"
$STATE_VERSION = 1

function _GetEmptyState {
    <#
    .SYNOPSIS
        Returns an empty state object
    #>
    return @{
        version = $STATE_VERSION
        dotfiles = @()
        environment = @{
            user = @()
            machine = @()
        }
        path = @{
            user = @{
                prepend = @()
                append = @()
            }
            machine = @{
                prepend = @()
                append = @()
            }
        }
        encrypted_files = @{}
        tasks = @{}
    }
}

function Get-WinixState {
    <#
    .SYNOPSIS
        Load state from state.json
    .DESCRIPTION
        Returns the current state. If file doesn't exist or is corrupted, returns empty state with warning.
    #>
    if (-not (Test-Path $STATE_FILE_PATH)) {
        return _GetEmptyState
    }

    try {
        $content = Get-Content -Path $STATE_FILE_PATH -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($content)) {
            Write-Warning "state.json is missing or corrupted. Starting with empty state."
            return _GetEmptyState
        }

        $state = $content | ConvertFrom-Json -AsHashtable

        if ($state.version -ne $STATE_VERSION) {
            Write-Error "state.json version mismatch. Expected: $STATE_VERSION, Found: $($state.version). Manual migration required."
            throw "State version mismatch"
        }

        $emptyState = _GetEmptyState

        $result = @{
            version = $state.version ?? $STATE_VERSION
            dotfiles = $state.dotfiles ?? @()
            environment = @{
                user = $state.environment?.user ?? @()
                machine = $state.environment?.machine ?? @()
            }
            path = @{
                user = @{
                    prepend = $state.path?.user?.prepend ?? @()
                    append = $state.path?.user?.append ?? @()
                }
                machine = @{
                    prepend = $state.path?.machine?.prepend ?? @()
                    append = $state.path?.machine?.append ?? @()
                }
            }
            encrypted_files = $state.encrypted_files ?? @{}
            tasks = $state.tasks ?? @{}
        }

        return $result
    }
    catch {
        if ($_.Exception.Message -eq "State version mismatch") {
            throw
        }
        Write-Warning "state.json is missing or corrupted. Starting with empty state."
        return _GetEmptyState
    }
}

function Save-WinixState {
    <#
    .SYNOPSIS
        Save state to state.json
    .PARAMETER State
        The state object to save
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State
    )

    $stateDir = Split-Path $STATE_FILE_PATH -Parent
    Ensure-Directory -Path $stateDir

    $State.version = $STATE_VERSION

    $json = $State | ConvertTo-Json -Depth 10
    Set-Content -Path $STATE_FILE_PATH -Value $json -Encoding UTF8 -NoNewline
}

function Add-DotfileToState {
    <#
    .SYNOPSIS
        Add a dotfile path to state
    .PARAMETER State
        The state object
    .PARAMETER Path
        The dotfile path to add (with trailing / for directories)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($State.dotfiles -notcontains $Path) {
        $State.dotfiles = @($State.dotfiles) + $Path
    }
}

function Remove-DotfileFromState {
    <#
    .SYNOPSIS
        Remove a dotfile path from state
    .PARAMETER State
        The state object
    .PARAMETER Path
        The dotfile path to remove
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $State.dotfiles = @($State.dotfiles | Where-Object { $_ -ne $Path })
}

function Add-EnvironmentToState {
    <#
    .SYNOPSIS
        Add an environment variable to state
    .PARAMETER State
        The state object
    .PARAMETER Name
        The environment variable name
    .PARAMETER Scope
        The scope (user or machine)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [ValidateSet("user", "machine")]
        [string]$Scope
    )

    if ($State.environment[$Scope] -notcontains $Name) {
        $State.environment[$Scope] = @($State.environment[$Scope]) + $Name
    }
}

function Remove-EnvironmentFromState {
    <#
    .SYNOPSIS
        Remove an environment variable from state
    .PARAMETER State
        The state object
    .PARAMETER Name
        The environment variable name
    .PARAMETER Scope
        The scope (user or machine)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [ValidateSet("user", "machine")]
        [string]$Scope
    )

    $State.environment[$Scope] = @($State.environment[$Scope] | Where-Object { $_ -ne $Name })
}

function Add-PathToState {
    <#
    .SYNOPSIS
        Add a PATH entry to state
    .PARAMETER State
        The state object
    .PARAMETER Path
        The path to add
    .PARAMETER Scope
        The scope (user or machine)
    .PARAMETER Position
        The position (prepend or append)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [ValidateSet("user", "machine")]
        [string]$Scope,
        [Parameter(Mandatory = $true)]
        [ValidateSet("prepend", "append")]
        [string]$Position
    )

    if ($State.path[$Scope][$Position] -notcontains $Path) {
        $State.path[$Scope][$Position] = @($State.path[$Scope][$Position]) + $Path
    }
}

function Remove-PathFromState {
    <#
    .SYNOPSIS
        Remove a PATH entry from state
    .PARAMETER State
        The state object
    .PARAMETER Path
        The path to remove
    .PARAMETER Scope
        The scope (user or machine)
    .PARAMETER Position
        The position (prepend or append)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [ValidateSet("user", "machine")]
        [string]$Scope,
        [Parameter(Mandatory = $true)]
        [ValidateSet("prepend", "append")]
        [string]$Position
    )

    $State.path[$Scope][$Position] = @($State.path[$Scope][$Position] | Where-Object { $_ -ne $Path })
}

function Add-EncryptedFileToState {
    <#
    .SYNOPSIS
        Add an encrypted file entry to state
    .PARAMETER State
        The state object
    .PARAMETER TargetPath
        The target path of the decrypted file
    .PARAMETER SourceHash
        The hash of the encrypted source file
    .PARAMETER TargetHash
        The hash of the decrypted target file
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,
        [Parameter(Mandatory = $true)]
        [string]$SourceHash,
        [Parameter(Mandatory = $true)]
        [string]$TargetHash
    )

    $State.encrypted_files[$TargetPath] = @{
        source_hash = $SourceHash
        target_hash = $TargetHash
    }
}

function Remove-EncryptedFileFromState {
    <#
    .SYNOPSIS
        Remove an encrypted file entry from state
    .PARAMETER State
        The state object
    .PARAMETER TargetPath
        The target path of the decrypted file
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $State.encrypted_files.Remove($TargetPath)
}

function Get-StateFilePath {
    <#
    .SYNOPSIS
        Returns the path to the state file
    #>
    return $STATE_FILE_PATH
}

function Get-TaskState {
    <#
    .SYNOPSIS
        Get state for a specific task
    .PARAMETER State
        The state object
    .PARAMETER TaskName
        The task name
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        [Parameter(Mandatory = $true)]
        [string]$TaskName
    )

    if (-not $State.tasks) {
        $State.tasks = @{}
    }

    if (-not $State.tasks[$TaskName]) {
        return @{ items = @() }
    }

    return $State.tasks[$TaskName]
}

function Add-TaskItemToState {
    <#
    .SYNOPSIS
        Add an item to task state
    .PARAMETER State
        The state object
    .PARAMETER TaskName
        The task name
    .PARAMETER Item
        The item to add (e.g., app ID)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        [Parameter(Mandatory = $true)]
        [string]$TaskName,
        [Parameter(Mandatory = $true)]
        [string]$Item
    )

    if (-not $State.tasks) {
        $State.tasks = @{}
    }

    if (-not $State.tasks[$TaskName]) {
        $State.tasks[$TaskName] = @{ items = @() }
    }

    if ($State.tasks[$TaskName].items -notcontains $Item) {
        $State.tasks[$TaskName].items = @($State.tasks[$TaskName].items) + $Item
    }
}

function Remove-TaskItemFromState {
    <#
    .SYNOPSIS
        Remove an item from task state
    .PARAMETER State
        The state object
    .PARAMETER TaskName
        The task name
    .PARAMETER Item
        The item to remove
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        [Parameter(Mandatory = $true)]
        [string]$TaskName,
        [Parameter(Mandatory = $true)]
        [string]$Item
    )

    if (-not $State.tasks -or -not $State.tasks[$TaskName]) {
        return
    }

    $State.tasks[$TaskName].items = @($State.tasks[$TaskName].items | Where-Object { $_ -ne $Item })
}

