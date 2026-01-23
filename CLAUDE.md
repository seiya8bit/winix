# winix

Declarative Environment Manager for Windows 11

## Documentation

| Document | Content |
|----------|---------|
| [docs/spec/](docs/spec/README.md) | Specifications (CLI, config file, behavior) |

## Common Commands

```powershell
winix status              # Show differences
winix apply               # Apply configuration
```

---

## Coding Conventions

### Naming Rules

| Target | Convention | Example |
|--------|------------|---------|
| Functions | PascalCase | `Get-PackageList`, `Install-DotFiles` |
| Variables | camelCase | `$configPath`, `$installedApps` |
| Constants | UPPER_SNAKE_CASE | `$STATE_FILE_PATH` |
| Private functions | Prefix with underscore | `_ValidateConfig` |

### Code Style

- Indentation: 4 spaces
- Strings: Prefer double quotes (for variable expansion), use single quotes for literals
- Pipelines: Place `|` at end of line and break to new line for long pipelines
- Comments: Write help comments (`.SYNOPSIS`, `.PARAMETER`) for functions

### Error Handling

- Set `$ErrorActionPreference = 'Stop'` at script beginning
- Wrap external commands in `try-catch`
- Output error messages with `Write-Error` (use `throw` only for fatal errors)

---

## Prohibited Practices

### Code Implementation

| Prohibited | Reason |
|------------|--------|
| CI environment branching like `if ($env:CI)` | Reliability decreases when code paths differ between production and CI |
| CI-specific skip processing or mocks | Same as above |
| Leaving unused code | Reduces readability, causes future confusion |
| Leaving commented-out code | Same as above |

### Work Process

| Prohibited | Reason |
|------------|--------|
| Completing work with "it probably works" | Code without verification cannot guarantee quality |
| Committing without verification | Same as above |
| Starting implementation without checking specifications | Causes requirement gaps and rework |

---

## Development Workflow

### Commit Messages

```
<type>: <summary>
```

| type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `refactor` | Refactoring |
| `docs` | Documentation |
| `chore` | Other |

### Workflow

1. **Preparation**: Read [specifications](docs/spec/README.md) and understand requirements
2. **Implementation**: Modify code
3. **Verification**: Confirm all commands work correctly
4. **Regression check**: Confirm existing features are not broken
5. **Completion**: Commit & push

### Verification (Required)

```powershell
winix --help
winix --version
winix status
winix apply
```

---

## Directory Structure

```
winix/
├── winix.ps1           # Entry point
├── bootstrap.ps1       # Initial setup
├── winix.yaml          # Configuration file
├── lib/                # Modules
├── dotfiles/           # Dotfiles source
├── secrets/            # Encrypted files
├── CLAUDE.md           # This file
├── README.md           # Public README (English)
└── docs/
    ├── ja/
    │   └── README.md   # Public README (Japanese)
    └── spec/           # Specifications
```
