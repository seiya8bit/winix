# winix

Declarative Environment Manager for Windows 11 (PowerShell 7).

winix syncs packages, dotfiles, environment variables, secrets, and custom tasks from a single YAML file.

## Features

- Scoop packages and buckets (full sync)
- Winget packages (additive)
- Dotfiles (copy-based)
- Environment variables and PATH (user/machine)
- age-encrypted files with optional Bitwarden CLI integration
- Custom tasks via `tasks/*.ps1`

## Requirements

- Windows 11
- PowerShell 7
- Scoop (auto-installed by bootstrap)
- Module: powershell-yaml (auto-installed by bootstrap)

Optional:
- gsudo (for machine-level env/PATH)
- age (for encrypted files)
- Bitwarden CLI (if using `age.bitwarden_item`)

## Quick Start

```powershell
# 1. Clone
# git clone https://github.com/<username>/winix.git
# cd winix

# 2. Bootstrap (installs Scoop, powershell-yaml, registers winix command)
.\bootstrap.ps1

# 3. Preview changes
winix status

# 4. Apply
winix apply
```

## Configuration

`winix.yaml` (or encrypted `winix.yaml.age`)

```yaml
packages:
  scoop:
    buckets:
      - main
      - extras
    apps:
      - git
      - neovim
  winget:
    apps:
      - Microsoft.PowerToys

dotfiles:
  source: "./dotfiles"
  target: "~"

environment:
  user:
    EDITOR: "nvim"
  path:
    user:
      append:
        - "%USERPROFILE%\\bin"

age:
  public_key: "age1..."
  bitwarden_item: "winix-age-key"

encrypted_files:
  - source: "./secrets/id_ed25519.age"
    target: "~/.ssh/id_ed25519"
    acl: private
```

## Commands

```powershell
winix status      # Preview changes (only preview mode)
winix apply       # Apply configuration
winix --help
winix --version

winix secret keygen [<path>]
winix secret encrypt <file>
winix secret decrypt <file>

winix config encrypt [--remove]
winix config decrypt [--force]
winix config cache-clear
```

## Specs

See `docs/spec/README.md` for full specifications.