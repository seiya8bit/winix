# winix Specifications

Declarative Environment Manager for Windows 11

## Overview

| Item | Description |
|------|-------------|
| Tool Name | winix |
| Platform | Windows 11 |
| Language | PowerShell 7 |
| Package Managers | Scoop, Winget |

## Documentation Structure

| File | Content |
|------|---------|
| [cli.md](cli.md) | CLI command reference |
| [config.md](config.md) | Configuration file (winix.yaml) reference |
| [behavior.md](behavior.md) | Behavior specifications (apply order, full sync, state management) |

## Feature List

### Package Management

- Declarative management using Scoop and Winget
- Version pinning via YAML (`name: "version"` for Scoop/Winget)
- Scoop uses full sync (packages/buckets not in config are removed, except `main` bucket)
- Winget is additive only (packages not in config are not removed)

### Dotfiles Management

- Copy-based approach (not symlinks)
- Copies while preserving directory structure
- Full sync (only files placed by winix are subject to removal)

### Environment Variable Management

- User-level (user) and machine-level (machine)
- PATH operations (prepend/append)
- Full sync (only those set by winix are subject to removal)

### Secrets Management

- Decrypt and deploy age-encrypted files
- Bitwarden CLI integration
- ACL settings (for SSH private keys, etc.)

### Task Feature

- Extension mechanism for custom processing
- Implementation via task files (`tasks/<name>.ps1`)
- Idempotent design (tasks manage their own state)

## Setup

```powershell
# 1. Clone repository
git clone https://github.com/<username>/winix.git
cd winix

# 2. Run bootstrap
.\bootstrap.ps1

# 3. Restart PowerShell
```

bootstrap.ps1 automatically executes:
1. Scoop installation (if not installed)
2. Register `winix` command to PowerShell profile
3. Run `winix apply`

## Requirements

| Tool | Purpose | Required |
|------|---------|----------|
| Scoop | Package management | Yes (auto-installed by bootstrap.ps1) |
| powershell-yaml | YAML config file parsing | Yes (auto-installed by bootstrap.ps1) |
| gsudo | machine environment/PATH settings | Only when using machine section |
| age | Secrets management | Only when using encrypted_files |
| Bitwarden CLI | Auto-retrieve keys | Only when using age.bitwarden_item |
| Winget | Package management | Only when using packages.winget |

## Directory Structure

```
winix/
├── winix.ps1           # Entry point
├── bootstrap.ps1       # Initial setup
├── winix.yaml          # Configuration file
├── lib/                # Modules
│   ├── Common.ps1      # Shared utilities
│   ├── Config.ps1      # Configuration file loading
│   ├── Packages.ps1    # Package management
│   ├── Winget.ps1      # Winget package management
│   ├── Dotfiles.ps1    # Dotfiles management
│   ├── Environment.ps1 # Environment variable management
│   ├── Secrets.ps1     # Secrets management
│   ├── State.ps1       # State management
│   ├── Ui.ps1          # UI helpers
│   └── Tasks.ps1       # Task management
├── tasks/              # Custom tasks
├── dotfiles/           # Dotfiles source
├── secrets/            # Encrypted files
├── CLAUDE.md           # Development guidelines
└── docs/
    └── spec/           # Specifications (this directory)
```
