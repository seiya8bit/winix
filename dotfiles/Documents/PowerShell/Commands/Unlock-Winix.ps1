function Unlock-Winix {
    <#
    .SYNOPSIS
        Unlock Bitwarden and set WINIX_AGE_KEY for winix commands.
    #>
    if (-not $env:BW_SESSION) {
        Write-Host "Unlocking Bitwarden..." -ForegroundColor Cyan
        $env:BW_SESSION = $(bw unlock --raw)
    }
    $env:WINIX_AGE_KEY = $(bw get notes 'winix-age-key')
    Write-Host "WINIX_AGE_KEY set." -ForegroundColor Green
}
