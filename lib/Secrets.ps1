<#
.SYNOPSIS
    Secrets management module for winix
.DESCRIPTION
    Manages age encryption/decryption and Bitwarden CLI integration
#>

$ErrorActionPreference = 'Stop'

function Test-AgeInstalled {
    <#
    .SYNOPSIS
        Check if age is installed
    #>
    $age = Get-Command age -ErrorAction SilentlyContinue
    return $null -ne $age
}

function Assert-AgeInstalled {
    <#
    .SYNOPSIS
        Assert that age is installed, error if not
    #>
    if (-not (Test-AgeInstalled)) {
        Write-Error "age is required for encrypted file operations. Install it via Scoop: scoop install age"
        throw "age not installed"
    }
}

function Test-BitwardenInstalled {
    <#
    .SYNOPSIS
        Check if Bitwarden CLI is installed
    #>
    $bw = Get-Command bw -ErrorAction SilentlyContinue
    return $null -ne $bw
}

function Assert-BitwardenReady {
    <#
    .SYNOPSIS
        Assert that Bitwarden CLI is installed and logged in
    #>
    if (-not (Test-BitwardenInstalled)) {
        Write-Error "Bitwarden CLI is required. Install it via Scoop: scoop install bitwarden-cli"
        throw "Bitwarden CLI not installed"
    }

    $status = bw status 2>&1 | ConvertFrom-Json
    if ($status.status -eq "unauthenticated") {
        Write-Error "Bitwarden CLI is not logged in. Run 'bw login' first."
        throw "Bitwarden not logged in"
    }

    if ($status.status -eq "locked") {
        Write-Error "Bitwarden vault is locked. Run 'bw unlock' and set BW_SESSION environment variable."
        throw "Bitwarden vault locked"
    }
}

function _GetAgeKeyFromBitwarden {
    <#
    .SYNOPSIS
        Get age secret key from Bitwarden item
    .PARAMETER ItemName
        The Bitwarden item name
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ItemName
    )

    Assert-BitwardenReady

    $itemJson = bw get item $ItemName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to get Bitwarden item: $ItemName"
        throw "Bitwarden item not found"
    }

    $item = $itemJson | ConvertFrom-Json

    if ($item.notes -and $item.notes -match "^AGE-SECRET-KEY-") {
        return $item.notes.Trim()
    }

    if ($item.fields) {
        $keyField = $item.fields | Where-Object { $_.name -eq "age_key" -or $_.name -eq "key" } | Select-Object -First 1
        if ($keyField -and $keyField.value -match "^AGE-SECRET-KEY-") {
            return $keyField.value.Trim()
        }
    }

    Write-Error "No age secret key found in Bitwarden item: $ItemName. Put the key in Notes field or a custom field named 'age_key' or 'key'."
    throw "Age key not found in Bitwarden item"
}

function _GetAgeKey {
    <#
    .SYNOPSIS
        Get age secret key from configured source
    .PARAMETER Config
        The age configuration
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    if ($env:WINIX_AGE_KEY) {
        return $env:WINIX_AGE_KEY
    }

    if ($env:WINIX_AGE_KEY_FILE) {
        $keyPath = Expand-WinixPath $env:WINIX_AGE_KEY_FILE
        if (-not (Test-Path $keyPath)) {
            Write-Error "Age key file not found: $keyPath"
            throw "Age key file not found"
        }
        $content = Get-Content -Path $keyPath -Raw
        $key = ($content -split "`n" | Where-Object { $_ -match "^AGE-SECRET-KEY-" } | Select-Object -First 1).Trim()
        if (-not $key) {
            Write-Error "No valid age secret key found in file: $keyPath"
            throw "Invalid age key file"
        }
        return $key
    }

    if ($env:WINIX_BITWARDEN_ITEM) {
        return _GetAgeKeyFromBitwarden -ItemName $env:WINIX_BITWARDEN_ITEM
    }

    if ($Config.bitwarden_item) {
        return _GetAgeKeyFromBitwarden -ItemName $Config.bitwarden_item
    }

    $keyFilePath = if ($Config.key_file) { $Config.key_file } else { $Config.age_key_file }
    if ($keyFilePath) {
        $keyPath = Expand-WinixPath $keyFilePath
        if (-not (Test-Path $keyPath)) {
            Write-Error "Age key file not found: $keyPath"
            throw "Age key file not found"
        }
        $content = Get-Content -Path $keyPath -Raw
        $key = ($content -split "`n" | Where-Object { $_ -match "^AGE-SECRET-KEY-" } | Select-Object -First 1).Trim()
        if (-not $key) {
            Write-Error "No valid age secret key found in file: $keyPath"
            throw "Invalid age key file"
        }
        return $key
    }

    Write-Error "No age key source configured. Set 'bitwarden_item' or 'key_file' in age section."
    throw "No age key configured"
}


function _ApplyAcl {
    <#
    .SYNOPSIS
        Apply ACL settings to a file
    .PARAMETER Path
        The file path
    .PARAMETER AclConfig
        The ACL configuration (preset string or detailed hashtable)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        $AclConfig
    )

    if (-not $AclConfig) {
        return
    }

    $acl = Get-Acl -Path $Path

    if ($AclConfig -is [string]) {
        switch ($AclConfig) {
            "private" {
                $acl.SetAccessRuleProtection($true, $false)
                $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null

                $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $currentUser,
                    [System.Security.AccessControl.FileSystemRights]::FullControl,
                    [System.Security.AccessControl.AccessControlType]::Allow
                )
                $acl.AddAccessRule($rule)
            }
            "read_only" {
                $acl.SetAccessRuleProtection($true, $false)
                $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null

                $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $currentUser,
                    [System.Security.AccessControl.FileSystemRights]::Read,
                    [System.Security.AccessControl.AccessControlType]::Allow
                )
                $acl.AddAccessRule($rule)
            }
            "default" {
                return
            }
        }
    }
    else {
        $inherit = if ($null -eq $AclConfig.inherit) { $true } else { $AclConfig.inherit }
        $acl.SetAccessRuleProtection(-not $inherit, $false)

        if (-not $inherit) {
            $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null
        }

        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $ownerRights = switch ($AclConfig.owner) {
            "full_control" { [System.Security.AccessControl.FileSystemRights]::FullControl }
            "read_write" { [System.Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [System.Security.AccessControl.FileSystemRights]::Write }
            "read" { [System.Security.AccessControl.FileSystemRights]::Read }
            default { [System.Security.AccessControl.FileSystemRights]::FullControl }
        }
        $ownerRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $currentUser,
            $ownerRights,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($ownerRule)

        if ($AclConfig.users -and $AclConfig.users -ne "none") {
            $usersRights = switch ($AclConfig.users) {
                "full_control" { [System.Security.AccessControl.FileSystemRights]::FullControl }
                "read_write" { [System.Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [System.Security.AccessControl.FileSystemRights]::Write }
                "read" { [System.Security.AccessControl.FileSystemRights]::Read }
            }
            if ($usersRights) {
                $usersRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    "BUILTIN\Users",
                    $usersRights,
                    [System.Security.AccessControl.AccessControlType]::Allow
                )
                $acl.AddAccessRule($usersRule)
            }
        }
    }

    Set-Acl -Path $Path -AclObject $acl
}

function Get-EncryptedFilesDiff {
    <#
    .SYNOPSIS
        Calculate differences for encrypted files
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
        toAdd = @()
        toUpdate = @()
        toRemove = @()
    }

    if (-not $Config.encrypted_files -or $Config.encrypted_files.Count -eq 0) {
        foreach ($targetPath in $State.encrypted_files.Keys) {
            $diff.toRemove += @{
                targetPath = $targetPath
                tildePath = $targetPath
            }
        }
        return $diff
    }

    $configTargets = @{}
    foreach ($file in $Config.encrypted_files) {
        $tildePath = Normalize-TildePath $file.target
        $configTargets[$tildePath] = $file
    }

    foreach ($file in $Config.encrypted_files) {
        $tildePath = Normalize-TildePath $file.target
        $sourceHash = Get-WinixFileHash -Path $file.source
        $targetHash = Get-WinixFileHash -Path $file.target
        $stateEntry = $State.encrypted_files[$tildePath]

        if (-not (Test-Path $file.target)) {
            $diff.toAdd += @{
                source = $file.source
                target = $file.target
                tildePath = $tildePath
                acl = $file.acl
            }
        }
        elseif (-not $stateEntry) {
            $diff.toUpdate += @{
                source = $file.source
                target = $file.target
                tildePath = $tildePath
                acl = $file.acl
                reason = "not tracked"
            }
        }
        elseif ($stateEntry.source_hash -ne $sourceHash) {
            $diff.toUpdate += @{
                source = $file.source
                target = $file.target
                tildePath = $tildePath
                acl = $file.acl
                reason = "source changed"
            }
        }
        elseif ($stateEntry.target_hash -ne $targetHash) {
            $diff.toUpdate += @{
                source = $file.source
                target = $file.target
                tildePath = $tildePath
                acl = $file.acl
                reason = "target modified"
            }
        }
    }

    foreach ($targetPath in $State.encrypted_files.Keys) {
        if (-not $configTargets.ContainsKey($targetPath)) {
            $diff.toRemove += @{
                targetPath = $targetPath
                tildePath = $targetPath
            }
        }
    }

    return $diff
}

function Invoke-EncryptedFilesApply {
    <#
    .SYNOPSIS
        Apply encrypted files changes
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

    $diff = Get-EncryptedFilesDiff -Config $Config -State $State
    $changes = 0

    $needsDecryption = $diff.toAdd.Count -gt 0 -or $diff.toUpdate.Count -gt 0

    if ($needsDecryption -and -not $DryRun) {
        Assert-AgeInstalled

        if ($Config.age -and $Config.age.bitwarden_item) {
            Assert-BitwardenReady
        }
    }

    foreach ($item in $diff.toRemove) {
        $fullPath = Expand-TildePath $item.targetPath
        if ($DryRun) {
            Write-Host "  - $($item.tildePath)" -ForegroundColor Red -NoNewline
            Write-Host "    (would remove)" -ForegroundColor DarkGray
        }
        else {
            Write-Host "  - $($item.tildePath)" -ForegroundColor Red -NoNewline
            try {
                if (Test-Path $fullPath) {
                    Remove-Item -Path $fullPath -Force
                }
                Remove-EncryptedFileFromState -State $State -TargetPath $item.tildePath
                Write-Host "    done" -ForegroundColor DarkGray
            }
            catch {
                Write-Host "    failed" -ForegroundColor Red
                throw
            }
        }
        $changes++
    }

    $ageKey = $null
    if ($needsDecryption -and -not $DryRun -and $Config.age) {
        $ageKey = _GetAgeKey -Config $Config.age
    }

    foreach ($item in $diff.toAdd) {
        if ($DryRun) {
            Write-Host "  + $($item.tildePath)" -ForegroundColor Green -NoNewline
            Write-Host "    (would decrypt and deploy)" -ForegroundColor DarkGray
        }
        else {
            Write-Host "  + $($item.tildePath)" -ForegroundColor Green -NoNewline
            try {
                $targetDir = Split-Path $item.target -Parent
                if (-not (Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }

                $tempKeyFile = [System.IO.Path]::GetTempFileName()
                try {
                    Set-Content -Path $tempKeyFile -Value $ageKey -NoNewline
                    $output = age --decrypt --identity $tempKeyFile --output $item.target $item.source 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        throw "age decrypt failed: $output"
                    }
                }
                finally {
                    Remove-Item -Path $tempKeyFile -Force -ErrorAction SilentlyContinue
                }

                if ($item.acl) {
                    _ApplyAcl -Path $item.target -AclConfig $item.acl
                }

                $sourceHash = Get-WinixFileHash -Path $item.source
                $targetHash = Get-WinixFileHash -Path $item.target
                Add-EncryptedFileToState -State $State -TargetPath $item.tildePath -SourceHash $sourceHash -TargetHash $targetHash

                Write-Host "    done" -ForegroundColor DarkGray
            }
            catch {
                Write-Host "    failed" -ForegroundColor Red
                throw
            }
        }
        $changes++
    }

    foreach ($item in $diff.toUpdate) {
        if ($DryRun) {
            Write-Host "  ~ $($item.tildePath)" -ForegroundColor Yellow -NoNewline
            Write-Host "    (would update, $($item.reason))" -ForegroundColor DarkGray
        }
        else {
            Write-Host "  ~ $($item.tildePath)" -ForegroundColor Yellow -NoNewline
            try {
                $tempKeyFile = [System.IO.Path]::GetTempFileName()
                try {
                    Set-Content -Path $tempKeyFile -Value $ageKey -NoNewline
                    $output = age --decrypt --identity $tempKeyFile --output $item.target $item.source 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        throw "age decrypt failed: $output"
                    }
                }
                finally {
                    Remove-Item -Path $tempKeyFile -Force -ErrorAction SilentlyContinue
                }

                if ($item.acl) {
                    _ApplyAcl -Path $item.target -AclConfig $item.acl
                }

                $sourceHash = Get-WinixFileHash -Path $item.source
                $targetHash = Get-WinixFileHash -Path $item.target
                Add-EncryptedFileToState -State $State -TargetPath $item.tildePath -SourceHash $sourceHash -TargetHash $targetHash

                Write-Host "    done" -ForegroundColor DarkGray
            }
            catch {
                Write-Host "    failed" -ForegroundColor Red
                throw
            }
        }
        $changes++
    }

    return @{ changes = $changes }
}

function Show-EncryptedFilesStatus {
    <#
    .SYNOPSIS
        Show encrypted files status differences
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

    $diff = Get-EncryptedFilesDiff -Config $Config -State $State

    $hasChanges = $diff.toAdd.Count -gt 0 -or
                  $diff.toUpdate.Count -gt 0 -or
                  $diff.toRemove.Count -gt 0

    if (-not $hasChanges) {
        return
    }

    Write-SectionHeader -Title "Encrypted Files"

    foreach ($item in $diff.toAdd) {
        Write-Host "  + $($item.tildePath)" -ForegroundColor Green
    }

    foreach ($item in $diff.toUpdate) {
        Write-Host "  ~ $($item.tildePath)" -ForegroundColor Yellow -NoNewline
        Write-Host "    ($($item.reason))" -ForegroundColor DarkGray
    }

    foreach ($item in $diff.toRemove) {
        Write-Host "  - $($item.tildePath)" -ForegroundColor Red
    }
}

function New-AgeKeyPair {
    <#
    .SYNOPSIS
        Generate a new age key pair
    .PARAMETER OutputPath
        Path to save the key file. Defaults to ~/.config/winix/key.txt
    #>
    param(
        [string]$OutputPath
    )

    Assert-AgeInstalled

    if (-not $OutputPath) {
        $OutputPath = Join-Path $env:USERPROFILE ".config\winix\key.txt"
    }

    $OutputPath = $OutputPath -replace '^~', $env:USERPROFILE

    $outputDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $output = age-keygen 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to generate key: $output"
        throw "Key generation failed"
    }

    Set-Content -Path $OutputPath -Value $output -NoNewline

    $acl = Get-Acl -Path $OutputPath
    $acl.SetAccessRuleProtection($true, $false)
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $currentUser,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $acl.AddAccessRule($rule)
    Set-Acl -Path $OutputPath -AclObject $acl

    $publicKey = ($output -split "`n" | Where-Object { $_ -match "^Public key:" } | Select-Object -First 1) -replace "^Public key:\s*", ""

    Write-Host "Key generated at: $OutputPath"
    Write-Host "Public key: $publicKey"

    return $publicKey
}

function Invoke-AgeEncrypt {
    <#
    .SYNOPSIS
        Encrypt a file with age
    .PARAMETER FilePath
        Path to the file to encrypt
    .PARAMETER Config
        The age configuration containing public_key
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    Assert-AgeInstalled

    $publicKey = $Config.public_key
    if (-not $publicKey) {
        Write-Error "age public key is not configured (use age.public_key)"
        throw "No public key configured"
    }

    if (-not (Test-Path $FilePath)) {
        Write-Error "File not found: $FilePath"
        throw "File not found"
    }

    $outputPath = "$FilePath.age"
    $output = age --encrypt --recipient $publicKey --output $outputPath $FilePath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Encryption failed: $output"
        throw "Encryption failed"
    }

    Write-Host "Encrypted: $outputPath"
    return $outputPath
}

function Invoke-AgeDecrypt {
    <#
    .SYNOPSIS
        Decrypt a file with age and output to stdout
    .PARAMETER FilePath
        Path to the encrypted file
    .PARAMETER Config
        The age configuration
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    Assert-AgeInstalled

    if (-not (Test-Path $FilePath)) {
        Write-Error "File not found: $FilePath"
        throw "File not found"
    }

    $ageKey = _GetAgeKey -Config $Config

    $tempKeyFile = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $tempKeyFile -Value $ageKey -NoNewline
        $output = age --decrypt --identity $tempKeyFile $FilePath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Decryption failed: $output"
            throw "Decryption failed"
        }
        return $output
    }
    finally {
        Remove-Item -Path $tempKeyFile -Force -ErrorAction SilentlyContinue
    }
}

