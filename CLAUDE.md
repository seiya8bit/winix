# winix

Declarative Environment Manager for Windows 11 (PowerShell 7).

## Specs / References

- `docs/spec/README.md` (entry point)
- `docs/spec/config.md` (winix.yaml / winix.yaml.age)
- `docs/spec/behavior.md`
- `docs/spec/cli.md`

## Common Commands

```powershell
winix status                  # Preview changes
winix apply                   # Apply configuration
winix config encrypt --remove # Encrypt winix.yaml -> winix.yaml.age
winix config decrypt --force  # Decrypt winix.yaml.age -> winix.yaml
winix secret encrypt <file>   # Encrypt file -> <file>.age
winix secret decrypt <file>   # Decrypt to stdout
```

## Encrypted Config Notes

- `winix.yaml` takes precedence if it exists.
- Encrypted config uses `winix.yaml.age`.
- Auto-decrypt uses env vars only:
  - `WINIX_AGE_KEY`
  - `WINIX_AGE_KEY_FILE`
  - `WINIX_BITWARDEN_ITEM`
- Bitwarden requires `bw login`, `bw unlock`, and `BW_SESSION` set.

## Coding Conventions

- Indent: 4 spaces
- Strings: double quotes for interpolation, single quotes for literals
- Private functions: `_Prefix` (underscore)
- Help comments for public functions (`.SYNOPSIS`, `.PARAMETER`)
- `$ErrorActionPreference = 'Stop'` at top of scripts
- Use `Write-Error` and `throw` only for fatal errors

## Output/UI Conventions

- Use `Write-UiBanner` and `Write-SectionHeader` for main sections.
- Keep per-item output to a single line where possible (avoid mixing tool output).

## Commit Messages

Free-form is OK. If using a prefix, prefer:

```
feat: ...
fix: ...
refactor: ...
docs: ...
chore: ...
```

## Directory Structure

```
winix/
├── winix.ps1           # Entry point
├── bootstrap.ps1       # Initial setup
├── winix.yaml          # Plain config (optional)
├── winix.yaml.age      # Encrypted config
├── lib/                # Modules
├── tasks/              # Custom tasks
├── dotfiles/           # Dotfiles source
├── secrets/            # Encrypted files (.age)
├── CLAUDE.md           # This file
├── README.md           # Public README (English)
└── docs/
    └── spec/           # Specifications
```
