# Auto-load custom commands
Get-ChildItem (Join-Path $PSScriptRoot "Commands") -Filter "*.ps1" |
    ForEach-Object { . $_.FullName }

# Shell integrations
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { zoxide init powershell --cmd cd | Out-String })
}

# fzf configuration
if (Get-Command fzf -ErrorAction SilentlyContinue) {
    $env:FZF_DEFAULT_COMMAND = 'fd --type f --hidden --exclude .git'
    $env:FZF_DEFAULT_OPTS = '--preview "bat --color=always --style=numbers --line-range=:100 {}"'
    $scoopModules = "$env:USERPROFILE\scoop\modules"
    if ((Test-Path $scoopModules) -and
        ($env:PSModulePath -notlike "*$scoopModules*")) {
        $env:PSModulePath = "$scoopModules;$env:PSModulePath"
    }
    if (Get-Module -ListAvailable PSFzf) {
        Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' `
            -PSReadlineChordReverseHistory 'Ctrl+r'
        Set-PSReadLineKeyHandler -Key 'Alt+c' -ScriptBlock {
            $dir = fd --type d --hidden --exclude .git | fzf
            if ($dir) {
                Set-Location $dir
                [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
            }
        }
    }
}

# Tool aliases
Set-Alias cat bat
Set-Alias cc claude
Set-Alias fly flyctl
Set-Alias ld lazydocker
Set-Alias lg lazygit
Set-Alias v nvim

# eza (ls replacement)
$script:EzaArgs = '--icons', '--git', '--header', '--time-style=long-iso'
Remove-Alias -Name ls
function ls { eza @script:EzaArgs $args }
function lla { eza -la @script:EzaArgs $args }
function tree { eza --tree --icons $args }

# Claude CLI
function ccskip { claude --dangerously-skip-permissions --chrome }
function ccu { npx ccusage@latest }

# Conflict resolution
Remove-Alias -Name ni -Force -ErrorAction SilentlyContinue
