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

### Decrypting the Config

```powershell
# Set Bitwarden as age key source
$env:WINIX_BITWARDEN_ITEM = "winix-age-key"

# Unlock Bitwarden
bw login
$env:BW_SESSION = (bw unlock --raw)

# Decrypt, edit, re-encrypt
winix config decrypt --force
nvim winix.yaml
winix config encrypt --remove
```
