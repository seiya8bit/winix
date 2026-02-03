function Update-System {
    if (Get-Command scoop -ea 0) {
        Write-Host "Updating Scoop..." -f Cyan
        scoop update && scoop update * && scoop cleanup *
    }
    if (Get-Command winget -ea 0) {
        Write-Host "Updating Winget..." -f Cyan
        $winixDir = "$env:USERPROFILE\Projects\Oss\winix"
        $content = $null
        if (Test-Path "$winixDir\winix.yaml") {
            $content = Get-Content "$winixDir\winix.yaml" -Raw -Encoding UTF8
        }
        elseif (Test-Path "$winixDir\winix.yaml.age") {
            if (-not $env:WINIX_AGE_KEY) { Unlock-Winix }
            $tmpKey = [System.IO.Path]::GetTempFileName()
            try {
                Set-Content $tmpKey -Value $env:WINIX_AGE_KEY -NoNewline
                $content = age --decrypt --identity $tmpKey "$winixDir\winix.yaml.age" 2>&1
                if ($LASTEXITCODE -ne 0) { $content = $null }
            }
            finally { Remove-Item $tmpKey -Force -ea 0 }
        }
        if ($content) {
            Import-Module powershell-yaml -ea Stop
            $yaml = ConvertFrom-Yaml $content
            $yaml.packages.winget.apps | Where-Object { $_ -is [string] } | ForEach-Object {
                winget upgrade $_ --include-unknown `
                    --accept-package-agreements --accept-source-agreements
            }
        }
    }
    if (Get-Command mise -ea 0) {
        Write-Host "Updating mise..." -f Cyan
        mise self-update
        mise upgrade
    }
}
