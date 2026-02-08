<#
.SYNOPSIS
    Visual Studio workload installation task for winix
.DESCRIPTION
    Installs Visual Studio workloads using VS Installer setup.exe
#>

$ErrorActionPreference = 'Stop'

function global:Get-TaskInfo {
    <#
    .SYNOPSIS
        Returns task information
    #>
    return @{
        Name        = "VS Workloads"
        Description = "Install Visual Studio workloads"
        Version     = "1.0.0"
    }
}

function global:_GetVsWherePath {
    <#
    .SYNOPSIS
        Get vswhere.exe path from VS Installer directory or PATH
    #>
    $vswhereInstaller = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhereInstaller) {
        return $vswhereInstaller
    }

    $inPath = Get-Command "vswhere.exe" -ErrorAction SilentlyContinue
    if ($inPath) {
        return $inPath.Source
    }

    return $null
}

function global:_GetVsInstallInfo {
    <#
    .SYNOPSIS
        Get VS installation path and product type using vswhere
    .PARAMETER VsWherePath
        Path to vswhere.exe
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$VsWherePath
    )

    try {
        $json = & $VsWherePath -latest -format json -utf8 2>$null | ConvertFrom-Json
        if (-not $json -or $json.Count -eq 0) {
            return $null
        }

        $vs = $json[0]
        $productId = $vs.productId  # e.g. Microsoft.VisualStudio.Product.Community
        $channelId = $vs.channelId  # e.g. VisualStudio.17.Release

        return @{
            InstallPath = $vs.installationPath
            ProductId   = $productId
            ChannelId   = $channelId
        }
    }
    catch {
        return $null
    }
}

function global:_GetVsSetupPath {
    <#
    .SYNOPSIS
        Get VS Installer setup.exe path
    #>
    $setupPath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
    if (Test-Path $setupPath) {
        return $setupPath
    }
    return $null
}

function global:_IsWorkloadInstalled {
    <#
    .SYNOPSIS
        Check if a specific workload is installed using vswhere -requires
    .PARAMETER VsWherePath
        Path to vswhere.exe
    .PARAMETER WorkloadId
        Workload ID (e.g. Microsoft.VisualStudio.Workload.NativeDesktop)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$VsWherePath,
        [Parameter(Mandatory = $true)]
        [string]$WorkloadId
    )

    try {
        $result = & $VsWherePath -latest -requires $WorkloadId -property installationPath 2>$null
        return (-not [string]::IsNullOrWhiteSpace($result))
    }
    catch {
        return $false
    }
}

function global:_GetWorkloadDisplayName {
    <#
    .SYNOPSIS
        Map workload ID to a human-readable display name
    .PARAMETER WorkloadId
        Workload ID
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkloadId
    )

    $names = @{
        'Microsoft.VisualStudio.Workload.NativeDesktop' = 'C++ によるデスクトップ開発'
        'Microsoft.VisualStudio.Workload.ManagedGame'   = 'Unity によるゲーム開発'
        'Microsoft.VisualStudio.Workload.NetWeb'        = 'ASP.NET と Web 開発'
        'Microsoft.VisualStudio.Workload.ManagedDesktop' = '.NET デスクトップ開発'
        'Microsoft.VisualStudio.Workload.Universal'     = 'ユニバーサル Windows プラットフォーム開発'
        'Microsoft.VisualStudio.Workload.Azure'         = 'Azure の開発'
        'Microsoft.VisualStudio.Workload.Python'        = 'Python 開発'
        'Microsoft.VisualStudio.Workload.Node'          = 'Node.js 開発'
        'Microsoft.VisualStudio.Workload.NativeMobile'  = 'C++ によるモバイル開発'
    }

    if ($names.ContainsKey($WorkloadId)) {
        return "$($names[$WorkloadId]) ($WorkloadId)"
    }
    return $WorkloadId
}

function global:Get-TaskStatus {
    <#
    .SYNOPSIS
        Get current workload installation status
    .PARAMETER Config
        Task configuration from winix.yaml
    .PARAMETER TaskState
        Task state from winix state.json (unused for this task)
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Config,
        [Parameter(Mandatory = $false)]
        $TaskState = @{}
    )

    $status = @{
        ToInstall = @()
        ToRemove  = @()
        UpToDate  = @()
    }

    $configWorkloads = @()
    if ($Config.workloads) {
        $configWorkloads = @($Config.workloads)
    }

    if ($configWorkloads.Count -eq 0) {
        return $status
    }

    $vswherePath = _GetVsWherePath
    if (-not $vswherePath) {
        Write-Warning "vswhere not found; skipping VS workload check"
        return $status
    }

    $vsInfo = _GetVsInstallInfo -VsWherePath $vswherePath
    if (-not $vsInfo) {
        Write-Warning "Visual Studio is not installed; skipping workload check"
        return $status
    }

    foreach ($workloadId in $configWorkloads) {
        $displayName = _GetWorkloadDisplayName -WorkloadId $workloadId
        if (_IsWorkloadInstalled -VsWherePath $vswherePath -WorkloadId $workloadId) {
            $status.UpToDate += $displayName
        }
        else {
            $status.ToInstall += $displayName
        }
    }

    return $status
}

function global:Invoke-TaskApply {
    <#
    .SYNOPSIS
        Install Visual Studio workloads
    .PARAMETER Config
        Task configuration from winix.yaml
    .PARAMETER TaskState
        Task state from winix state.json (unused for this task)
    .PARAMETER DryRun
        If set, only show what would be done
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Config,
        [Parameter(Mandatory = $false)]
        $TaskState = @{},
        [switch]$DryRun
    )

    $result = @{
        installed = @()
        removed   = @()
    }

    $configWorkloads = @()
    if ($Config.workloads) {
        $configWorkloads = @($Config.workloads)
    }

    if ($configWorkloads.Count -eq 0) {
        return $result
    }

    $vswherePath = _GetVsWherePath
    if (-not $vswherePath) {
        Write-Warning "vswhere not found; skipping VS workload install"
        return $result
    }

    $vsInfo = _GetVsInstallInfo -VsWherePath $vswherePath
    if (-not $vsInfo) {
        Write-Warning "Visual Studio is not installed; skipping workload install"
        return $result
    }

    $setupPath = _GetVsSetupPath
    if (-not $setupPath) {
        Write-Warning "VS Installer setup.exe not found; skipping workload install"
        return $result
    }

    # Collect workloads that need installing
    $toInstall = @()
    foreach ($workloadId in $configWorkloads) {
        if (_IsWorkloadInstalled -VsWherePath $vswherePath -WorkloadId $workloadId) {
            $result.installed += $workloadId
        }
        else {
            $toInstall += $workloadId
        }
    }

    if ($toInstall.Count -eq 0) {
        return $result
    }

    if ($DryRun) {
        return $result
    }

    # Build setup.exe arguments
    $addArgs = @()
    foreach ($workloadId in $toInstall) {
        $addArgs += "--add"
        $addArgs += $workloadId
    }

    $setupArgs = @(
        "modify"
        "--installPath", "`"$($vsInfo.InstallPath)`""
    ) + $addArgs + @(
        "--passive"
        "--norestart"
        "--includeRecommended"
    )

    $displayNames = ($toInstall | ForEach-Object { _GetWorkloadDisplayName -WorkloadId $_ }) -join ", "
    Write-Host "    Installing: $displayNames" -ForegroundColor DarkGray

    $process = Start-Process -FilePath $setupPath -ArgumentList $setupArgs -Verb RunAs -PassThru -WindowStyle Hidden
    $process.WaitForExit()

    if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
        # 3010 = success, reboot required
        foreach ($workloadId in $toInstall) {
            $displayName = _GetWorkloadDisplayName -WorkloadId $workloadId
            if (_IsWorkloadInstalled -VsWherePath $vswherePath -WorkloadId $workloadId) {
                $result.installed += $workloadId
                Write-Host "    Installed: $displayName" -ForegroundColor Green
            }
            else {
                Write-Warning "Workload may not have been fully installed: $displayName"
            }
        }
        if ($process.ExitCode -eq 3010) {
            Write-Host "    Reboot recommended to complete installation" -ForegroundColor Yellow
        }
    }
    else {
        Write-Warning "VS Installer exited with code $($process.ExitCode)"
    }

    return $result
}

function global:Invoke-TaskCleanup {
    <#
    .SYNOPSIS
        Clean up task-specific helper functions
    #>
    Remove-Item -Path "Function:\_GetVsWherePath" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetVsInstallInfo" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetVsSetupPath" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_IsWorkloadInstalled" -ErrorAction SilentlyContinue
    Remove-Item -Path "Function:\_GetWorkloadDisplayName" -ErrorAction SilentlyContinue
}
