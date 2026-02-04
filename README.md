# winix

Declarative environment manager for Windows 11.
Define your packages, dotfiles, and tasks in YAML — apply them with a single command.

## Quick Start

```powershell
# 1. Bootstrap (first time only)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
irm https://raw.githubusercontent.com/seiya8bit/winix/main/bootstrap.ps1 | iex

# 2. Preview changes
winix status

# 3. Apply configuration
winix apply
```

## Features

| Feature | Description |
|---------|-------------|
| **Scoop** | Full sync (adds missing, removes unlisted) |
| **Winget** | Additive install (no removal) |
| **Dotfiles** | Copy files to target locations |
| **Tasks** | Run custom PowerShell scripts |
| **Environment** | Set variables and PATH entries |
| **Secrets** | Manage age-encrypted files |

## Commands

```powershell
# Core
winix status              # Preview pending changes
winix apply               # Apply configuration
winix --help              # Show help
winix --version           # Show version

# Secrets
winix secret keygen       # Generate age key pair
winix secret encrypt <f>  # Encrypt file -> <file>.age
winix secret decrypt <f>  # Decrypt file to stdout

# Config
winix config encrypt      # Encrypt winix.yaml -> winix.yaml.age
winix config decrypt      # Decrypt winix.yaml.age -> winix.yaml
winix config cache-clear  # Clear decrypted config cache
```

## Configuration

Define your environment in `winix.yaml`:

```yaml
scoop:
  buckets: [extras, nerd-fonts]
  packages: [git, neovim, ripgrep]

winget:
  packages:
    - Microsoft.VisualStudioCode
    - Mozilla.Firefox

dotfiles:
  source: "./dotfiles"
  target: "~"

tasks:
  - name: setup-shell
    path: "./tasks/setup-shell.ps1"
```

See [docs/spec/config.md](docs/spec/config.md) for full configuration options.

## Requirements

- Windows 11
- PowerShell 7
- Scoop

All requirements are installed automatically by `bootstrap.ps1`.

## Documentation

- [Specification Overview](docs/spec/README.md)
- [Configuration Reference](docs/spec/config.md)
- [Behavior Details](docs/spec/behavior.md)
- [CLI Reference](docs/spec/cli.md)

---

## About This Branch

This branch (`seiya8bit-setup`) is a personal configuration that includes:

- Encrypted config (`winix.yaml.age`) — plain `winix.yaml` is not tracked
- Custom dotfiles and tasks
- Encrypted secrets using age + Bitwarden

### Setup from Scratch (New PC)

Steps to set up a fresh Windows 11 machine.

#### 1. Check out this branch

```powershell
git checkout seiya8bit-setup
```

#### 2. Install Scoop

Open PowerShell and run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
```

#### 3. Install required tools

```powershell
scoop bucket add extras
scoop install git
scoop install pwsh
scoop install age
scoop install bitwarden-cli
scoop install extras/wezterm
```

> **Note:** After installing `pwsh` (PowerShell 7), open a new terminal (e.g. WezTerm) and run `pwsh`. All following steps should be run in PowerShell 7.

#### 4. Run bootstrap

```powershell
.\bootstrap.ps1
```

This will automatically install any missing prerequisites (Scoop, PowerShell 7, etc.).

#### 5. Check status

```powershell
.\winix.ps1 status
```

This previews pending changes. If everything looks good, run `.\winix.ps1 apply` to apply them.

### Decrypting the Config

To edit the encrypted config (`winix.yaml.age`):

```powershell
# Set Bitwarden as age key source
$env:WINIX_BITWARDEN_ITEM = "winix-age-key"

# Log in to Bitwarden and get a session
bw login
$env:BW_SESSION = (bw unlock --raw)

# Decrypt, edit, re-encrypt
winix config decrypt --force
nvim winix.yaml
winix config encrypt --remove
```
