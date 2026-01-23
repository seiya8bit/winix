# winix

Personal Windows 11 environment setup using winix.
This branch tracks my packages, dotfiles, tasks, and encrypted secrets for a clean machine bootstrap.

## What This Branch Includes

- Scoop packages (full sync) and Winget packages (additive)
- Dotfiles under `dotfiles/`
- Custom tasks under `tasks/`
- Encrypted files under `secrets/` (age)
- Encrypted configuration `winix.yaml.age`

## Requirements

- Windows 11
- PowerShell 7 (installed by bootstrap)
- Scoop (installed by bootstrap)
- Module: powershell-yaml (installed by bootstrap)

Required for this branch:

- gsudo (for machine-level env/PATH and ACL updates)
- age (for encrypted files)
- Bitwarden CLI (for age key via Bitwarden)

## Encrypted Config & Secrets

This branch stores the config as `winix.yaml.age`.
The plain `winix.yaml` is not tracked.

Set Bitwarden as the default source for the age key:

```powershell
$env:WINIX_BITWARDEN_ITEM = "winix-age-key"
```

Bitwarden CLI flow (required for this branch):

```powershell
bw login
$env:BW_SESSION = (bw unlock --raw)
```

## Branch Notes

- `winix.yaml.age` is the source of truth.
- `dotfiles/` and `tasks/` are customized for this branch.
- If you need to edit the config:

```powershell
winix config decrypt --force
nvim winix.yaml
winix config encrypt --remove
```

## Commands

```powershell
winix status
winix apply
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
