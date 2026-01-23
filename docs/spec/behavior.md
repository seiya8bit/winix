# Behavior Specifications

## apply Execution Order

```
1. scoop packages (buckets → apps)
2. winget packages
3. environment (user → machine)
4. path (user → machine)
5. dotfiles
6. encrypted_files
7. tasks
```

---

## Full Sync

winix adopts a **full sync** approach. It synchronizes the actual environment with the state defined in the configuration file.

### Sync Targets and Deletion Rules

| Target | Tracking Method | Deletion Target |
|--------|-----------------|-----------------|
| Scoop Packages/Buckets | Managed by Scoop | All not in config are deleted when packages.scoop is configured (except `main` bucket) |
| Winget Packages | Managed by Winget | Additive only (packages not in config are NOT removed) |
| dotfiles | Tracked in state.json | Only files placed by winix |
| Environment variables | Tracked in state.json | Only those set by winix |
| PATH | Tracked in state.json | Only paths added by winix |
| Encrypted files | Tracked in state.json | Only files placed by winix |

### Scoop Package Full Sync

All packages and buckets installed via Scoop are sync targets when the `packages.scoop` (or legacy `packages`) section is configured.

- Packages/buckets not in winix.yaml are deleted when `packages` is configured
- Not recorded in state.json since Scoop manages state
- `scoop` package itself is excluded from deletion (required for Scoop operation)
- `main` bucket is excluded from deletion (Scoop's default bucket)
- If a Scoop install reports "requires admin rights", winix installs `gsudo` (if missing) and retries with elevation.

### Winget Package Management (Additive Only)

Unlike Scoop, Winget uses **additive only** mode - packages not in config are NOT removed.

- Packages in winix.yaml are installed if not present
- Packages not in winix.yaml are left untouched (not removed)
- Not recorded in state.json since Winget manages installed state
- Version-pinned packages are installed with specific version and skipped during updates

**Rationale:**

- Many system apps are managed by winget and shouldn't be removed automatically
- Users typically have many winget packages they don't want to track declaratively

**Limitations:**

- Winget export format doesn't include version information, so version mismatch detection is not supported
- Version-pinned packages are installed with the specified version, but subsequent version changes cannot be automatically detected

### File/Environment Variable Full Sync

Only items placed/set by winix are deletion targets.

- Manually created files and environment variables are not affected
- Only items tracked in state.json are deletion targets
- If a section is omitted from config, all tracked items in that section are removed on apply (dotfiles, environment variables, PATH entries, encrypted files).

### Dotfiles Tracking Behavior

- If a target file already exists with identical content but is not tracked in state.json, winix starts tracking it (no copy occurs). This is shown as `=` in status/apply output.

---

## Status vs Apply

- `winix status` runs the **same execution path** as `winix apply` with DryRun, but **never changes** the system.
- `winix apply` executes changes and updates `state.json`.
- Because status uses the same path, it may still require external tools (e.g., Scoop/Winget) when those sections are configured.

---

## State Management (state.json)

### File Location

```
~/.config/winix/state.json
```

### Structure

```json
{
  "version": 1,
  "dotfiles": [
    "~/.gitconfig",
    "~/.config/starship.toml",
    "~/.config/empty-dir/"
  ],
  "environment": {
    "user": ["EDITOR", "MY_VAR"],
    "machine": ["SOME_VAR"]
  },
  "path": {
    "user": {
      "prepend": ["%USERPROFILE%\\bin"],
      "append": ["%USERPROFILE%\\.local\\bin"]
    },
    "machine": {
      "append": ["C:\\tools\\bin"]
    }
  },
  "encrypted_files": {
    "~/.ssh/id_ed25519": {
      "source_hash": "SHA256_HASH_OF_ENCRYPTED_SOURCE",
      "target_hash": "SHA256_HASH_OF_DECRYPTED_TARGET"
    }
  }
}
```

### dotfiles Format

- File: `~/.gitconfig` (no trailing slash)
- Empty directory: `~/.config/empty-dir/` (trailing slash)

### encrypted_files Format

- `source_hash`: Hash of encrypted source file
- `target_hash`: Hash of decrypted target file
- Re-decrypts when target file is manually modified
- If a target file exists but is not tracked in state.json, it is treated as an update and overwritten (re-decrypted).

### Version Management

| Situation | Behavior |
|-----------|----------|
| New section added | version unchanged |
| Format changed | version incremented |
| Version mismatch | Error and abort, prompt manual migration |

### Behavior on Corruption/Deletion

1. If `state.json` is missing, winix starts with empty state (no warning).
2. If `state.json` is empty or corrupted, winix shows a warning and uses empty state.
3. state.json is rebuilt on next successful apply completion

### Tasks State

state.json includes a `tasks` section to track task-managed items.

```json
{
  "tasks": {
    "fonts": {
      "items": ["HackGen", "PlemolJP"]
    }
  }
}
```

**Auto-tracking:** During apply, when a task has no changes to apply, winix still records any `task.config.apps` items into state.json so they are tracked going forward.

---

## Prerequisite Checks

Prerequisites are checked right before each section executes.
Status runs the same code path as apply (DryRun), so checks still apply when a section is about to run.

| Check Target | Required for Status | Required for Apply | Condition |
|--------------|---------------------|--------------------|-----------|
| Scoop | Yes | Yes | When Scoop section has changes (config present) |
| Winget | Yes | Yes | When Winget section has changes (config present) |
| gsudo | No | Yes | When machine env/PATH changes are needed |
| age | No | Yes | Only when encrypted_files add/update exists |
| Bitwarden CLI | No | Yes | When encrypted_files add/update exists and `age.bitwarden_item` is set |

※ age/Bitwarden are required for decryption (add/update), not for removals.

### Check Details

#### Scoop

- Verify `scoop` command exists
- Abort with error if not installed

#### Winget

- Verify `winget` command exists
- Abort with error if not installed (Windows Package Manager is typically pre-installed on Windows 11)

#### gsudo

- Verify `gsudo` command exists
- Abort with error if not installed
- Including gsudo in packages.apps allows it to work during bootstrap

#### age

- Verify `age` command exists
- Abort with error if not installed

#### Bitwarden CLI

- Verify `bw` command exists
- Check login status with `bw status`
- Error if not logged in or locked

---

## Conflict Resolution

### dotfiles

When conflict with existing file: **Always overwrite**

### encrypted_files

When conflict with existing file: **Always overwrite**

### Environment Variables

When conflict with existing environment variable: **Overwrite**

### PATH

When path already exists:
- Start tracking it (no modification)
- Shown as `=` in output, and recorded in state.json

---

## Design Principles

### Extensibility

Designed to add features while maintaining backward compatibility.

#### winix.yaml Loading

- Unknown sections are ignored (not an error)
- Accommodates future section additions

#### state.json Loading

- Non-existent sections are treated as empty
- Accommodates future section additions

```powershell
$state = Get-Content $path | ConvertFrom-Json
$dotfiles = $state.dotfiles ?? @()
$environment = $state.environment ?? @{ user = @(); machine = @() }
```

#### packages.apps Internal Format

Accepts both string and hash formats, normalizes internally.

```yaml
# YAML (input)
apps:
  - git
  - nodejs: "20.10.0"
```

```powershell
# Internal format (normalized)
@(
    @{ name = "git"; version = $null }
    @{ name = "nodejs"; version = "20.10.0" }
)
```

### Backward Compatibility Policy

| Target | Policy |
|--------|--------|
| winix.yaml | New section additions don't affect existing config. Existing sections are never deprecated |
| state.json | No version change for new section additions. Version incremented only on format changes |
| CLI | New option additions don't affect existing command behavior |
