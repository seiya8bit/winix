<#
.SYNOPSIS
    Task management module for winix
.DESCRIPTION
    Manages custom tasks defined in tasks/*.ps1 files
#>

$ErrorActionPreference = 'Stop'

function _GetTasksDir {
    <#
    .SYNOPSIS
        Get the tasks directory path
    #>
    return Join-Path $PSScriptRoot "..\tasks"
}

function Get-AvailableTasks {
    <#
    .SYNOPSIS
        Get list of available task files
    #>
    $tasksDir = _GetTasksDir

    if (-not (Test-Path $tasksDir)) {
        return @()
    }

    $taskFiles = Get-ChildItem -Path $tasksDir -Filter "*.ps1" -File
    return @($taskFiles | ForEach-Object { $_.BaseName })
}

function _LoadTask {
    <#
    .SYNOPSIS
        Load a task file and return its functions
    .PARAMETER TaskName
        The task name (without .ps1 extension)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskName
    )

    $tasksDir = _GetTasksDir
    $taskPath = Join-Path $tasksDir "$TaskName.ps1"

    if (-not (Test-Path $taskPath)) {
        Write-Error "Task file not found: $taskPath"
        throw "Task not found"
    }

    # Load task file - functions must be defined with global: scope
    . $taskPath

    if (-not (Get-Command "Get-TaskInfo" -ErrorAction SilentlyContinue)) {
        Write-Error "Task '$TaskName' is missing required function: Get-TaskInfo"
        throw "Invalid task: missing Get-TaskInfo"
    }

    if (-not (Get-Command "Get-TaskStatus" -ErrorAction SilentlyContinue)) {
        Write-Error "Task '$TaskName' is missing required function: Get-TaskStatus"
        throw "Invalid task: missing Get-TaskStatus"
    }

    if (-not (Get-Command "Invoke-TaskApply" -ErrorAction SilentlyContinue)) {
        Write-Error "Task '$TaskName' is missing required function: Invoke-TaskApply"
        throw "Invalid task: missing Invoke-TaskApply"
    }
}

function Get-TasksDiff {
    <#
    .SYNOPSIS
        Get status differences for all configured tasks
    .PARAMETER Config
        The normalized configuration
    .PARAMETER State
        The winix state object
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [Parameter(Mandatory = $true)]
        [hashtable]$State
    )

    $diff = @{
        tasks = @()
    }

    if (-not $Config.tasks -or $Config.tasks.Count -eq 0) {
        return $diff
    }

    foreach ($taskName in $Config.tasks.Keys) {
        $taskConfig = $Config.tasks[$taskName]
        $taskState = Get-TaskState -State $State -TaskName $taskName

        try {
            _LoadTask -TaskName $taskName

            $info = Get-TaskInfo
            $status = Get-TaskStatus -Config $taskConfig -TaskState $taskState

            $diff.tasks += @{
                name = $taskName
                info = $info
                status = $status
                config = $taskConfig
            }
        }
        catch {
            Write-Warning "Failed to load task '$taskName': $_"
        }
        finally {
            # Call task-specific cleanup if defined
            if (Get-Command "Invoke-TaskCleanup" -ErrorAction SilentlyContinue) {
                Invoke-TaskCleanup
            }
            # Clean up standard task interface functions
            Remove-Item -Path "Function:\Get-TaskInfo" -ErrorAction SilentlyContinue
            Remove-Item -Path "Function:\Get-TaskStatus" -ErrorAction SilentlyContinue
            Remove-Item -Path "Function:\Invoke-TaskApply" -ErrorAction SilentlyContinue
            Remove-Item -Path "Function:\Invoke-TaskRollback" -ErrorAction SilentlyContinue
            Remove-Item -Path "Function:\Invoke-TaskCleanup" -ErrorAction SilentlyContinue
        }
    }

    return $diff
}

function Invoke-TasksApply {
    <#
    .SYNOPSIS
        Apply all configured tasks
    .PARAMETER Config
        The normalized configuration
    .PARAMETER State
        The winix state object
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

    $changes = 0

    if (-not $Config.tasks -or $Config.tasks.Count -eq 0) {
        return @{ changes = 0 }
    }

    $diff = Get-TasksDiff -Config $Config -State $State

    foreach ($task in $diff.tasks) {
        if ($task.status.ToInstall.Count -eq 0 -and
            $task.status.ToRemove.Count -eq 0 -and
            $task.status.UpToDate.Count -gt 0) {
            continue
        }

        $taskState = Get-TaskState -State $State -TaskName $task.name

        try {
            _LoadTask -TaskName $task.name

            Write-SectionHeader -Title ("Task / " + $task.name)

            if ($task.status.ToInstall) {
                foreach ($item in $task.status.ToInstall) {
                    if ($DryRun) {
                        Write-Host "  + $item" -ForegroundColor Green -NoNewline
                        Write-Host "    (would install)" -ForegroundColor DarkGray
                    }
                    else {
                        Write-Host "  + $item" -ForegroundColor Green
                    }
                    $changes++
                }
            }

            if ($task.status.ToRemove) {
                foreach ($item in $task.status.ToRemove) {
                    if ($DryRun) {
                        Write-Host "  - $item" -ForegroundColor Red -NoNewline
                        Write-Host "    (would remove)" -ForegroundColor DarkGray
                    }
                    else {
                        Write-Host "  - $item" -ForegroundColor Red
                    }
                    $changes++
                }
            }

            if (-not $DryRun) {
                $result = Invoke-TaskApply -Config $task.config -TaskState $taskState

                # Update state based on task result
                if ($result -and $result.installed) {
                    foreach ($item in $result.installed) {
                        Add-TaskItemToState -State $State -TaskName $task.name -Item $item
                    }
                }
                if ($result -and $result.removed) {
                    foreach ($item in $result.removed) {
                        Remove-TaskItemFromState -State $State -TaskName $task.name -Item $item
                    }
                }
            }
        }
        catch {
            Write-Error "Task '$($task.name)' failed: $_"
            throw
        }
        finally {
            # Call task-specific cleanup if defined
            if (Get-Command "Invoke-TaskCleanup" -ErrorAction SilentlyContinue) {
                Invoke-TaskCleanup
            }
            # Clean up standard task interface functions
            Remove-Item -Path "Function:\Get-TaskInfo" -ErrorAction SilentlyContinue
            Remove-Item -Path "Function:\Get-TaskStatus" -ErrorAction SilentlyContinue
            Remove-Item -Path "Function:\Invoke-TaskApply" -ErrorAction SilentlyContinue
            Remove-Item -Path "Function:\Invoke-TaskRollback" -ErrorAction SilentlyContinue
            Remove-Item -Path "Function:\Invoke-TaskCleanup" -ErrorAction SilentlyContinue
        }
    }

    return @{ changes = $changes }
}

function Show-TasksStatus {
    <#
    .SYNOPSIS
        Show status of all configured tasks
    .PARAMETER Config
        The normalized configuration
    .PARAMETER State
        The winix state object
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [Parameter(Mandatory = $true)]
        [hashtable]$State
    )

    if (-not $Config.tasks -or $Config.tasks.Count -eq 0) {
        return
    }

    $diff = Get-TasksDiff -Config $Config -State $State

    $hasChanges = $false
    foreach ($task in $diff.tasks) {
        if ($task.status.ToInstall.Count -gt 0 -or $task.status.ToRemove.Count -gt 0) {
            $hasChanges = $true
            break
        }
    }

    if (-not $hasChanges) {
        return
    }

    foreach ($task in $diff.tasks) {
        if ($task.status.ToInstall.Count -eq 0 -and $task.status.ToRemove.Count -eq 0) {
            continue
        }

        Write-SectionHeader -Title ("Task / " + $task.name)

        if ($task.status.ToInstall) {
            foreach ($item in $task.status.ToInstall) {
                Write-Host "  + $item" -ForegroundColor Green
            }
        }

        if ($task.status.ToRemove) {
            foreach ($item in $task.status.ToRemove) {
                Write-Host "  - $item" -ForegroundColor Red
            }
        }
    }
}

