function Update-System {
    if (Get-Command scoop -ea 0) {
        Write-Host "Updating Scoop..." -f Cyan
        scoop update && scoop update * && scoop cleanup *
    }
    if (Get-Command winget -ea 0) {
        Write-Host "Updating Winget..." -f Cyan
        $srcDir = if (Get-Command chezmoi -ea 0) {
            chezmoi source-path
        } else { "$HOME/.local/share/chezmoi/home" }
        $scriptsDir = Join-Path (Split-Path $srcDir) "scripts"
        . "$scriptsDir/Get-AppsConfig.ps1"
        $cfg = Get-AppsConfig -SourceDir $srcDir
        $cfg.winget_apps | Where-Object { -not $_.version } | ForEach-Object {
            winget upgrade $_.id --include-unknown `
                --accept-package-agreements --accept-source-agreements
        }
    }
    if (Get-Command mise -ea 0) {
        Write-Host "Updating mise..." -f Cyan
        mise self-update
        mise upgrade
    }
}
