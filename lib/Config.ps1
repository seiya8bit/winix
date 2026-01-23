<#
.SYNOPSIS
    Configuration loading module for winix
.DESCRIPTION
    Loads and normalizes winix.yaml configuration file
    Supports encrypted configuration files (winix.yaml.age)
#>

$ErrorActionPreference = 'Stop'

$script:CONFIG_CACHE_DIR = Join-Path $env:USERPROFILE ".config\winix\cache"
$script:CONFIG_CACHE_FILE = Join-Path $script:CONFIG_CACHE_DIR "config.yaml"
$script:CONFIG_CACHE_HASH = Join-Path $script:CONFIG_CACHE_DIR "config.yaml.hash"

function _GetAgeKeyForConfig {
    <#
    .SYNOPSIS
        Get age secret key for decrypting config file
    .DESCRIPTION
        Tries to get the age key from:
        1. WINIX_AGE_KEY environment variable (direct key)
        2. WINIX_AGE_KEY_FILE environment variable (path to key file)
        3. WINIX_BITWARDEN_ITEM environment variable (Bitwarden item name)
    #>

    # Try direct key from environment
    if ($env:WINIX_AGE_KEY) {
        return $env:WINIX_AGE_KEY
    }

    # Try key file path from environment
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

    # Try Bitwarden item from environment
    if ($env:WINIX_BITWARDEN_ITEM) {
        $bw = Get-Command bw -ErrorAction SilentlyContinue
        if (-not $bw) {
            Write-Error "Bitwarden CLI is required when using WINIX_BITWARDEN_ITEM. Install it via Scoop: scoop install bitwarden-cli"
            throw "Bitwarden CLI not installed"
        }

        $status = bw status 2>&1 | ConvertFrom-Json
        if ($status.status -ne "unlocked") {
            Write-Error "Bitwarden vault must be unlocked. Run 'bw unlock' and set BW_SESSION."
            throw "Bitwarden not ready"
        }

        $itemJson = bw get item $env:WINIX_BITWARDEN_ITEM 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to get Bitwarden item: $($env:WINIX_BITWARDEN_ITEM)"
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

        Write-Error "No age secret key found in Bitwarden item: $($env:WINIX_BITWARDEN_ITEM)"
        throw "Age key not found in Bitwarden item"
    }

    Write-Error @"
No age key configured for decrypting winix.yaml.age.
Set one of the following environment variables:
  - WINIX_AGE_KEY: The age secret key directly
  - WINIX_AGE_KEY_FILE: Path to file containing the age secret key
  - WINIX_BITWARDEN_ITEM: Bitwarden item name containing the age key
"@
    throw "No age key configured"
}

function _DecryptConfigFile {
    <#
    .SYNOPSIS
        Decrypt encrypted config file with caching
    .PARAMETER EncryptedPath
        Path to the encrypted config file (winix.yaml.age)
    .RETURNS
        Path to the decrypted config file (cached)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$EncryptedPath
    )

    # Check if age is installed
    $age = Get-Command age -ErrorAction SilentlyContinue
    if (-not $age) {
        Write-Error "age is required to decrypt winix.yaml.age. Install it via Scoop: scoop install age"
        throw "age not installed"
    }

    # Ensure cache directory exists
    Ensure-Directory -Path $script:CONFIG_CACHE_DIR

    # Calculate hash of encrypted file
    $currentHash = Get-WinixFileHash -Path $EncryptedPath

    # Check if cache is valid
    if ((Test-Path $script:CONFIG_CACHE_FILE) -and (Test-Path $script:CONFIG_CACHE_HASH)) {
        $cachedHash = Get-Content -Path $script:CONFIG_CACHE_HASH -Raw -ErrorAction SilentlyContinue
        if ($cachedHash -and $cachedHash.Trim() -eq $currentHash) {
            # Cache is valid, return cached file
            return $script:CONFIG_CACHE_FILE
        }
    }

    # Cache is invalid or doesn't exist, decrypt
    $ageKey = _GetAgeKeyForConfig

    $tempKeyFile = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $tempKeyFile -Value $ageKey -NoNewline
        $output = age --decrypt --identity $tempKeyFile --output $script:CONFIG_CACHE_FILE $EncryptedPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to decrypt config file: $output"
            throw "Config decryption failed"
        }

        # Save hash for cache validation
        Set-Content -Path $script:CONFIG_CACHE_HASH -Value $currentHash -NoNewline

        return $script:CONFIG_CACHE_FILE
    }
    finally {
        Remove-Item -Path $tempKeyFile -Force -ErrorAction SilentlyContinue
    }
}

function _ResolveConfigPath {
    <#
    .SYNOPSIS
        Resolve the config file path, handling encrypted configs
    .PARAMETER BasePath
        Base path to look for config file (without extension)
    .RETURNS
        Hashtable with 'path' (resolved path) and 'encrypted' (bool)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    $plainPath = $BasePath
    $encryptedPath = "$BasePath.age"

    # Prefer plain config if it exists
    if (Test-Path $plainPath) {
        return @{
            path = $plainPath
            encrypted = $false
        }
    }

    # Fall back to encrypted config
    if (Test-Path $encryptedPath) {
        $decryptedPath = _DecryptConfigFile -EncryptedPath $encryptedPath
        return @{
            path = $decryptedPath
            encrypted = $true
            originalPath = $encryptedPath
        }
    }

    return $null
}

function _NormalizeBuckets {
    <#
    .SYNOPSIS
        Normalize buckets configuration
    #>
    param(
        [array]$Buckets
    )

    if (-not $Buckets) {
        return @()
    }

    $result = @()
    foreach ($bucket in $Buckets) {
        if ($bucket -is [string]) {
            $result += @{ name = $bucket; url = $null }
        }
        elseif ($bucket -is [hashtable] -or $bucket -is [System.Collections.Specialized.OrderedDictionary]) {
            foreach ($key in $bucket.Keys) {
                $result += @{ name = $key; url = $bucket[$key] }
            }
        }
    }
    return $result
}

function _NormalizeApps {
    <#
    .SYNOPSIS
        Normalize apps configuration (for Scoop)
    #>
    param(
        [array]$Apps
    )

    if (-not $Apps) {
        return @()
    }

    $result = @()
    foreach ($app in $Apps) {
        if ($app -is [string]) {
            $result += @{ name = $app; version = $null }
        }
        elseif ($app -is [hashtable] -or $app -is [System.Collections.Specialized.OrderedDictionary]) {
            foreach ($key in $app.Keys) {
                $result += @{ name = $key; version = $app[$key] }
            }
        }
    }
    return $result
}

function _NormalizeWingetApps {
    <#
    .SYNOPSIS
        Normalize Winget apps configuration
    #>
    param(
        [array]$Apps
    )

    if (-not $Apps) {
        return @()
    }

    $result = @()
    foreach ($app in $Apps) {
        if ($app -is [string]) {
            $result += @{ name = $app; version = $null }
        }
        elseif ($app -is [hashtable] -or $app -is [System.Collections.Specialized.OrderedDictionary]) {
            foreach ($key in $app.Keys) {
                $result += @{ name = $key; version = $app[$key] }
            }
        }
    }
    return $result
}

function _NormalizeEnvironment {
    <#
    .SYNOPSIS
        Normalize environment configuration
    #>
    param(
        [hashtable]$Environment
    )

    $result = @{
        user = @{}
        machine = @{}
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
    }

    if (-not $Environment) {
        return $result
    }

    if ($Environment.user) {
        foreach ($key in $Environment.user.Keys) {
            $result.user[$key] = $Environment.user[$key]
        }
    }

    if ($Environment.machine) {
        foreach ($key in $Environment.machine.Keys) {
            $result.machine[$key] = $Environment.machine[$key]
        }
    }

    if ($Environment.path) {
        if ($Environment.path.user) {
            if ($Environment.path.user.prepend) {
                $result.path.user.prepend = @($Environment.path.user.prepend)
            }
            if ($Environment.path.user.append) {
                $result.path.user.append = @($Environment.path.user.append)
            }
        }
        if ($Environment.path.machine) {
            if ($Environment.path.machine.prepend) {
                $result.path.machine.prepend = @($Environment.path.machine.prepend)
            }
            if ($Environment.path.machine.append) {
                $result.path.machine.append = @($Environment.path.machine.append)
            }
        }
    }

    return $result
}

function _NormalizeEncryptedFiles {
    <#
    .SYNOPSIS
        Normalize encrypted_files configuration
    #>
    param(
        [array]$EncryptedFiles,
        [string]$ConfigDir
    )

    if (-not $EncryptedFiles) {
        return @()
    }

    $result = @()
    foreach ($file in $EncryptedFiles) {
        $sourcePath = $file.source
        if ($sourcePath -match '^\.[\\/]') {
            $sourcePath = Join-Path $ConfigDir ($sourcePath -replace '^\.[\\/]', '')
        }
        else {
            $sourcePath = Expand-WinixPath $sourcePath
        }

        $targetPath = Expand-WinixPath $file.target

        $aclConfig = $null
        if ($file.acl) {
            if ($file.acl -is [string]) {
                $aclConfig = $file.acl
            }
            else {
                $aclConfig = @{
                    owner = $file.acl.owner ?? "full_control"
                    users = $file.acl.users ?? "none"
                    inherit = $file.acl.inherit ?? $false
                }
            }
        }

        $result += @{
            source = $sourcePath
            target = $targetPath
            acl = $aclConfig
        }
    }
    return $result
}

function Get-WinixConfig {
    <#
    .SYNOPSIS
        Load and normalize winix.yaml configuration
    .PARAMETER ConfigPath
        Path to the configuration file. Defaults to winix.yaml in the script directory.
        Supports encrypted config files (winix.yaml.age) with automatic caching.
    #>
    param(
        [string]$ConfigPath
    )

    $basePath = $ConfigPath
    $configDir = $null
    $actualConfigPath = $null

    if (-not $basePath) {
        $basePath = Get-WinixConfigPath
    }

    # Handle encrypted config files
    $resolved = _ResolveConfigPath -BasePath $basePath
    if (-not $resolved) {
        # Also try with .age extension removed if user specified it
        if ($basePath -match '\.age$') {
            $basePath = $basePath -replace '\.age$', ''
            $resolved = _ResolveConfigPath -BasePath $basePath
        }
    }

    if (-not $resolved) {
        Write-Error "Configuration file not found: $basePath (or $basePath.age)"
        throw "Configuration file not found"
    }

    $actualConfigPath = $resolved.path

    # For encrypted configs, configDir should be the original file's directory
    if ($resolved.encrypted) {
        $configDir = Split-Path $resolved.originalPath -Parent
    }
    else {
        $configDir = Split-Path (Resolve-Path $actualConfigPath) -Parent
    }

    $content = Get-Content -Path $actualConfigPath -Raw -Encoding UTF8
    $yaml = ConvertFrom-Yaml $content

    $config = @{
        packages = @{
            buckets = @()
            apps = @()
            winget = @{
                apps = @()
            }
        }
        dotfiles = $null
        environment = @{
            user = @{}
            machine = @{}
            path = @{
                user = @{ prepend = @(); append = @() }
                machine = @{ prepend = @(); append = @() }
            }
        }
        age = $null
        encrypted_files = @()
        tasks = @{}
        _configDir = $configDir
    }

    if ($yaml.packages) {
        # Support nested format (packages.scoop) and legacy format (packages.buckets/apps)
        if ($yaml.packages.scoop) {
            # New nested format: packages.scoop.buckets, packages.scoop.apps
            $config.packages.buckets = _NormalizeBuckets $yaml.packages.scoop.buckets
            $config.packages.apps = _NormalizeApps $yaml.packages.scoop.apps
        }
        else {
            # Legacy format: packages.buckets, packages.apps
            $config.packages.buckets = _NormalizeBuckets $yaml.packages.buckets
            $config.packages.apps = _NormalizeApps $yaml.packages.apps
        }

        # Winget packages
        if ($yaml.packages.winget -and $yaml.packages.winget.apps) {
            $config.packages.winget.apps = _NormalizeWingetApps $yaml.packages.winget.apps
        }
    }

    if ($yaml.dotfiles) {
        $sourcePath = $yaml.dotfiles.source
        if ($sourcePath -match '^\.[\\/]') {
            $sourcePath = Join-Path $configDir ($sourcePath -replace '^\.[\\/]', '')
        }
        else {
            $sourcePath = Expand-WinixPath $sourcePath
        }

        $config.dotfiles = @{
            source = $sourcePath
            target = Expand-WinixPath $yaml.dotfiles.target
        }
    }

    if ($yaml.environment) {
        $config.environment = _NormalizeEnvironment $yaml.environment
    }

    if ($yaml.age) {
        $config.age = @{
            public_key = $yaml.age.public_key
            key_file = if ($yaml.age.key_file) { Expand-WinixPath $yaml.age.key_file } else { $null }
            bitwarden_item = $yaml.age.bitwarden_item
        }
    }

    if ($yaml.encrypted_files) {
        $config.encrypted_files = _NormalizeEncryptedFiles $yaml.encrypted_files $configDir
    }

    if ($yaml.tasks) {
        $config.tasks = $yaml.tasks
    }

    return $config
}

function Get-ConfigDir {
    <#
    .SYNOPSIS
        Get the directory containing the winix.yaml file
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    return $Config._configDir
}

function Update-WinixYaml {
    <#
    .SYNOPSIS
        Update winix.yaml with new configuration
    .PARAMETER ConfigPath
        Path to the configuration file
    .PARAMETER Packages
        Updated packages configuration
    #>
    param(
        [string]$ConfigPath,
        [hashtable]$Packages
    )

    if (-not $ConfigPath) {
        $ConfigPath = Get-WinixConfigPath
    }

    $content = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
    $yaml = ConvertFrom-Yaml $content

    if ($Packages) {
        # Detect if using nested format (packages.scoop or packages.winget)
        $useNestedFormat = $yaml.packages -and ($yaml.packages.scoop -or $yaml.packages.winget)

        if ($useNestedFormat) {
            # Nested format
            if (-not $yaml.packages) {
                $yaml.packages = @{}
            }

            # Scoop packages
            if ($Packages.buckets -or $Packages.apps) {
                if (-not $yaml.packages.scoop) {
                    $yaml.packages.scoop = @{}
                }

                if ($Packages.buckets -and $Packages.buckets.Count -gt 0) {
                    $yaml.packages.scoop.buckets = @()
                    foreach ($bucket in $Packages.buckets) {
                        if ($bucket.url) {
                            $yaml.packages.scoop.buckets += @{ $bucket.name = $bucket.url }
                        }
                        else {
                            $yaml.packages.scoop.buckets += $bucket.name
                        }
                    }
                }

                if ($Packages.apps -and $Packages.apps.Count -gt 0) {
                    $yaml.packages.scoop.apps = @()
                    foreach ($app in $Packages.apps) {
                        if ($app.version) {
                            $yaml.packages.scoop.apps += @{ $app.name = $app.version }
                        }
                        else {
                            $yaml.packages.scoop.apps += $app.name
                        }
                    }
                }
            }

            # Winget packages
            if ($Packages.winget -and $Packages.winget.apps) {
                if (-not $yaml.packages.winget) {
                    $yaml.packages.winget = @{}
                }

                if ($Packages.winget.apps.Count -gt 0) {
                    $yaml.packages.winget.apps = @()
                    foreach ($app in $Packages.winget.apps) {
                        if ($app.version) {
                            $yaml.packages.winget.apps += @{ $app.name = $app.version }
                        }
                        else {
                            $yaml.packages.winget.apps += $app.name
                        }
                    }
                }
                else {
                    $yaml.packages.Remove('winget')
                }
            }
        }
        else {
            # Legacy format (keep backward compatibility)
            $yaml.packages = @{}

            if ($Packages.buckets -and $Packages.buckets.Count -gt 0) {
                $yaml.packages.buckets = @()
                foreach ($bucket in $Packages.buckets) {
                    if ($bucket.url) {
                        $yaml.packages.buckets += @{ $bucket.name = $bucket.url }
                    }
                    else {
                        $yaml.packages.buckets += $bucket.name
                    }
                }
            }

            if ($Packages.apps -and $Packages.apps.Count -gt 0) {
                $yaml.packages.apps = @()
                foreach ($app in $Packages.apps) {
                    if ($app.version) {
                        $yaml.packages.apps += @{ $app.name = $app.version }
                    }
                    else {
                        $yaml.packages.apps += $app.name
                    }
                }
            }

            # If winget apps are being added, switch to nested format
            if ($Packages.winget -and $Packages.winget.apps -and $Packages.winget.apps.Count -gt 0) {
                # Convert to nested format
                $scoopConfig = @{}
                if ($yaml.packages.buckets) {
                    $scoopConfig.buckets = $yaml.packages.buckets
                }
                if ($yaml.packages.apps) {
                    $scoopConfig.apps = $yaml.packages.apps
                }

                $yaml.packages = @{}
                if ($scoopConfig.buckets -or $scoopConfig.apps) {
                    $yaml.packages.scoop = $scoopConfig
                }

                $yaml.packages.winget = @{
                    apps = @()
                }
                foreach ($app in $Packages.winget.apps) {
                    if ($app.version) {
                        $yaml.packages.winget.apps += @{ $app.name = $app.version }
                    }
                    else {
                        $yaml.packages.winget.apps += $app.name
                    }
                }
            }
        }
    }

    $newContent = ConvertTo-Yaml $yaml
    Set-Content -Path $ConfigPath -Value $newContent -Encoding UTF8 -NoNewline
}

function Clear-ConfigCache {
    <#
    .SYNOPSIS
        Clear the decrypted config cache
    .DESCRIPTION
        Removes the cached decrypted config file, forcing re-decryption on next load
    #>

    $removed = $false

    if (Test-Path $script:CONFIG_CACHE_FILE) {
        Remove-Item -Path $script:CONFIG_CACHE_FILE -Force
        $removed = $true
    }

    if (Test-Path $script:CONFIG_CACHE_HASH) {
        Remove-Item -Path $script:CONFIG_CACHE_HASH -Force
        $removed = $true
    }

    if ($removed) {
        Write-Host "Config cache cleared"
    }
    else {
        Write-Host "No cache to clear"
    }
}

function Invoke-ConfigDecrypt {
    <#
    .SYNOPSIS
        Decrypt winix.yaml.age to winix.yaml
    .PARAMETER EncryptedPath
        Path to the encrypted config file. Defaults to winix.yaml.age in the script directory.
    .PARAMETER OutputPath
        Path for the decrypted output. Defaults to winix.yaml (removes .age extension).
    .PARAMETER Force
        If set, overwrites existing plain config file
    #>
    param(
        [string]$EncryptedPath,
        [string]$OutputPath,
        [switch]$Force
    )

    # Check if age is installed
    $age = Get-Command age -ErrorAction SilentlyContinue
    if (-not $age) {
        Write-Error "age is required. Install it via Scoop: scoop install age"
        throw "age not installed"
    }

    if (-not $EncryptedPath) {
        $EncryptedPath = "$(Get-WinixConfigPath).age"
    }

    if (-not (Test-Path $EncryptedPath)) {
        Write-Error "Encrypted config file not found: $EncryptedPath"
        throw "Encrypted config file not found"
    }

    if (-not $OutputPath) {
        $OutputPath = $EncryptedPath -replace '\.age$', ''
    }

    # Check if output file already exists
    if ((Test-Path $OutputPath) -and -not $Force) {
        Write-Error "Output file already exists: $OutputPath. Use --force to overwrite."
        throw "Output file exists"
    }

    # Try to read key source hints from plain config if it exists and env var is not set
    $plainConfigPath = $EncryptedPath -replace '\.age$', ''
    if ((Test-Path $plainConfigPath) -and -not $env:WINIX_BITWARDEN_ITEM -and -not $env:WINIX_AGE_KEY -and -not $env:WINIX_AGE_KEY_FILE) {
        try {
            $content = Get-Content -Path $plainConfigPath -Raw -Encoding UTF8
            $yaml = ConvertFrom-Yaml $content
            if ($yaml.age -and $yaml.age.bitwarden_item) {
                $env:WINIX_BITWARDEN_ITEM = $yaml.age.bitwarden_item
                Write-Host "Using age.bitwarden_item from config: $($yaml.age.bitwarden_item)"
            }
            elseif ($yaml.age -and $yaml.age.key_file) {
                $env:WINIX_AGE_KEY_FILE = Expand-WinixPath $yaml.age.key_file
                Write-Host "Using age.key_file from config: $($yaml.age.key_file)"
            }
        }
        catch {
            # Ignore errors reading plain config
        }
    }

    # Get age key for decryption
    $ageKey = _GetAgeKeyForConfig

    $tempKeyFile = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $tempKeyFile -Value $ageKey -NoNewline
        $output = age --decrypt --identity $tempKeyFile --output $OutputPath $EncryptedPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Decryption failed: $output"
            throw "Decryption failed"
        }

        Write-Host "Decrypted config saved to: $OutputPath"
        return $OutputPath
    }
    finally {
        Remove-Item -Path $tempKeyFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-ConfigEncrypt {
    <#
    .SYNOPSIS
        Encrypt winix.yaml to winix.yaml.age
    .PARAMETER ConfigPath
        Path to the plain config file. Defaults to winix.yaml in the script directory.
    .PARAMETER PublicKey
        The age public key to use for encryption. If not specified, uses the key from the config.
    .PARAMETER RemoveOriginal
        If set, removes the original plain config file after encryption
    #>
    param(
        [string]$ConfigPath,
        [string]$PublicKey,
        [switch]$RemoveOriginal
    )

    # Check if age is installed
    $age = Get-Command age -ErrorAction SilentlyContinue
    if (-not $age) {
        Write-Error "age is required. Install it via Scoop: scoop install age"
        throw "age not installed"
    }

    if (-not $ConfigPath) {
        $ConfigPath = Get-WinixConfigPath
    }

    if (-not (Test-Path $ConfigPath)) {
        Write-Error "Configuration file not found: $ConfigPath"
        throw "Configuration file not found"
    }

    # Get public key from config if not specified
    if (-not $PublicKey) {
        $content = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
        $yaml = ConvertFrom-Yaml $content
        if ($yaml.age -and $yaml.age.public_key) {
            $PublicKey = $yaml.age.public_key
        }
        else {
            Write-Error "No public key specified and no age.public_key found in config"
            throw "No public key available"
        }
    }

    $outputPath = "$ConfigPath.age"

    $output = age --encrypt --recipient $PublicKey --output $outputPath $ConfigPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Encryption failed: $output"
        throw "Encryption failed"
    }

    Write-Host "Encrypted config saved to: $outputPath"

    if ($RemoveOriginal) {
        Remove-Item -Path $ConfigPath -Force
        Write-Host "Removed original config: $ConfigPath"
    }

    return $outputPath
}

