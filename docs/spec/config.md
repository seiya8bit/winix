# Configuration File Reference

## Overview

| Item | Description |
|------|-------------|
| Filename | `winix.yaml` or `winix.yaml.age` (encrypted) |
| Format | YAML |
| Encoding | UTF-8 (BOM-less recommended, BOM also accepted) |
| Default location | Repository root (`winix.yaml`) |

### Encrypted Config Support

winix supports encrypted configuration files for storing sensitive data securely in version control.

| File | Description |
|------|-------------|
| `winix.yaml` | Plain text config (preferred when exists) |
| `winix.yaml.age` | age-encrypted config (used when `winix.yaml` not found) |

**To use encrypted config:**

1. Configure `age.public_key` in age section
2. Run `winix config encrypt --remove`
3. Set decryption key via environment variable:
   - `WINIX_AGE_KEY`: Direct secret key
   - `WINIX_AGE_KEY_FILE`: Path to key file
   - `WINIX_BITWARDEN_ITEM`: Bitwarden item name

See [CLI Reference](cli.md#encrypted-config-support) for details.

**Behavior note:**
- Automatic decryption of `winix.yaml.age` uses **environment variables only** (`WINIX_AGE_KEY`, `WINIX_AGE_KEY_FILE`, `WINIX_BITWARDEN_ITEM`).
- The **`winix config decrypt`** command is the only place where winix may read hints from an existing plain `winix.yaml` (e.g., `age.bitwarden_item` or `age.key_file`) to set those environment variables.

---

## Complete Configuration Example

```yaml
# Package management (nested format)
packages:
  scoop:
    buckets:
      - main
      - extras
      - my-bucket: "https://github.com/user/my-scoop-bucket"
    apps:
      - git
      - gsudo
      - neovim
      - nodejs: "20.10.0"    # Version pinned

  winget:
    apps:
      - Microsoft.PowerToys
      - Microsoft.VisualStudioCode: "1.85.0"  # Version pinned

# dotfiles
dotfiles:
  source: "./dotfiles"
  target: "~"

# Environment variables
environment:
  user:
    EDITOR: "nvim"
    MY_VAR: "value"
  machine:
    SOME_VAR: "value"
  path:
    user:
      prepend:
        - "%USERPROFILE%\\bin"
      append:
        - "%USERPROFILE%\\.local\\bin"
    machine:
      append:
        - "C:\\tools\\bin"

# Age (encryption key source)
age:
  public_key: "age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  bitwarden_item: "winix-age-key"
  # key_file: "~/.config/winix/key.txt"

# Encrypted files
encrypted_files:
  - source: "./secrets/credentials.age"
    target: "~/.config/app/credentials.json"
  - source: "./secrets/id_ed25519.age"
    target: "~/.ssh/id_ed25519"
    acl: private
```

---

## Section Details

### packages

Manage packages via Scoop and Winget.

#### Configuration Format

Two formats are supported:

**Nested format (recommended when using both Scoop and Winget):**

```yaml
packages:
  scoop:
    buckets:
      - main
      - extras
    apps:
      - git
      - nodejs: "20.10.0"

  winget:
    apps:
      - Microsoft.PowerToys
      - Microsoft.VisualStudioCode: "1.85.0"
```

**Legacy format (Scoop only, backward compatible):**

```yaml
packages:
  buckets:
    - main
    - extras
  apps:
    - git
    - nodejs: "20.10.0"
```

#### packages.scoop.buckets (or packages.buckets)

```yaml
packages:
  scoop:
    buckets:
      - main                                              # Official bucket
      - extras                                            # Official bucket
      - my-bucket: "https://github.com/user/bucket"      # Custom bucket
```

| Format | Description |
|--------|-------------|
| `- name` | Official bucket or already registered bucket |
| `- name: "url"` | Add custom bucket with URL |

#### packages.scoop.apps (or packages.apps)

```yaml
packages:
  scoop:
    apps:
      - git                    # Latest version
      - nodejs: "20.10.0"      # Version pinned
```

| Format | Description |
|--------|-------------|
| `- app` | Install latest version |
| `- app: "version"` | Install and pin specified version |

#### packages.winget.apps

```yaml
packages:
  winget:
    apps:
      - Microsoft.PowerToys                    # Latest version
      - Microsoft.VisualStudioCode: "1.85.0"   # Version pinned
```

| Format | Description |
|--------|-------------|
| `- id` | Install latest version using Winget package ID |
| `- id: "version"` | Install and pin specified version |

**Note:** Package IDs must match Winget's package ID format (e.g., `Microsoft.PowerToys`, `Git.Git`)

---

### dotfiles

Manage dotfiles using copy method.

```yaml
dotfiles:
  source: "./dotfiles"       # Source directory
  target: "~"                # Target base directory
```

| Key | Description | Example |
|-----|-------------|---------|
| `source` | Source directory | `"./dotfiles"`, `"C:\\dotfiles"` |
| `target` | Target base directory | `"~"`, `"C:\\Users\\user"` |

**Behavior:**
- Copies from `source` to `target` while preserving directory structure
- Example: `./dotfiles/.config/app/config.json` → `~/.config/app/config.json`

---

### environment

Manage environment variables.

#### environment.user / environment.machine

```yaml
environment:
  user:                      # User-level environment variables
    EDITOR: "nvim"
    MY_VAR: "value"
  machine:                   # Machine-level environment variables (requires gsudo)
    SOME_VAR: "value"
```

| Scope | Description | Requirements |
|-------|-------------|--------------|
| `user` | Current user only | None |
| `machine` | All users | Requires gsudo |

#### environment.path

Manipulate PATH environment variable.

```yaml
environment:
  path:
    user:
      prepend:               # Add to beginning of PATH (high priority)
        - "%USERPROFILE%\\bin"
      append:                # Add to end of PATH
        - "%USERPROFILE%\\.local\\bin"
    machine:
      prepend:
        - "C:\\tools\\priority"
      append:
        - "C:\\tools\\bin"
```

| Operation | Description |
|-----------|-------------|
| `prepend` | Add to beginning of PATH (prioritized in command search) |
| `append` | Add to end of PATH |

**Notes:**
- Machine-side operations require gsudo
- Paths already in PATH are not modified; they are marked for tracking (`=`).

---

### age

Encryption key management (preferred).

```yaml
age:
  public_key: "age1..."                # Public key for encryption
  key_file: "~/.config/winix/key.txt"  # Secret key file for decryption
  bitwarden_item: "winix-age-key"      # Retrieve secret key from Bitwarden
```

| Key | Description |
|-----|-------------|
| `public_key` | age public key for encryption |
| `key_file` | Path to age secret key file for decryption |
| `bitwarden_item` | Bitwarden CLI item name to retrieve secret key |

**Key retrieval priority (encrypted_files + secret decrypt):**
1. `WINIX_AGE_KEY` / `WINIX_AGE_KEY_FILE` / `WINIX_BITWARDEN_ITEM`
2. `age.bitwarden_item`
3. `age.key_file` (or legacy `age.age_key_file`)

**Bitwarden integration:**

Set the secret key in Bitwarden item using one of these methods (in priority order):

1. **Notes field**: Put secret key directly in Notes
2. **Custom field**: Set in custom field named `age_key` or `key`

```
Item name: winix-age-key
# Method 1: Put directly in Notes
Notes: AGE-SECRET-KEY-1XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# Method 2: Use custom field
Custom fields:
  - Name: age_key (or key)
  - Value: AGE-SECRET-KEY-1XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

Must login with `bw login` and set `$env:BW_SESSION` beforehand.

---

### encrypted_files

Manage decryption and deployment of encrypted files.

```yaml
encrypted_files:
  - source: "./secrets/credentials.age"
    target: "~/.config/app/credentials.json"

  - source: "./secrets/id_ed25519.age"
    target: "~/.ssh/id_ed25519"
    acl: private
```

| Key | Description | Required |
|-----|-------------|----------|
| `source` | Path to encrypted file (.age) | Yes |
| `target` | Path to deploy decrypted file | Yes |
| `acl` | Access control setting | No (default: default) |

#### ACL Settings

**Presets:**

| Preset | Description | Use Case |
|--------|-------------|----------|
| `private` | Owner only full access, inheritance disabled | SSH private keys, API keys |
| `read_only` | Owner only read access, inheritance disabled | Read-only sensitive files |
| `default` | Inherit parent folder ACL | Normal files (when omitted) |

**Detailed specification:**

```yaml
encrypted_files:
  - source: "./secrets/shared_config.age"
    target: "~/.config/app/config.json"
    acl:
      owner: full_control
      users: read
      inherit: false
```

| Key | Values | Description |
|-----|--------|-------------|
| `owner` | `full_control`, `read_write`, `read` | Owner permissions |
| `users` | `full_control`, `read_write`, `read`, `none` | Users group permissions |
| `inherit` | `true`, `false` | Inherit from parent folder |

**Defaults for detailed ACL:** `owner=full_control`, `users=none`, `inherit=false`

---

### tasks

Manage custom task configuration.

```yaml
tasks:
  fonts:
    source: "./fonts"
    apps:
      - "HackGen"
      - "PlemolJP"
```

| Key | Description |
|-----|-------------|
| `<task-name>` | Task name (corresponds to `tasks/<task-name>.ps1`) |

**Task configuration content:**

Each task's configuration content is task-specific. Processed by corresponding `tasks/<task-name>.ps1` file.
If a task uses `apps`, winix can auto-track those items in state.json (see behavior spec).

**Required functions in task file:**

| Function | Description |
|----------|-------------|
| `global:Get-TaskInfo` | Return task info (Name, Description, Version) |
| `global:Get-TaskStatus` | Return current status (ToInstall, ToRemove, UpToDate) |
| `global:Invoke-TaskApply` | Execute task (supports DryRun switch) |
| `global:Invoke-TaskRollback` | (Optional) Rollback task changes |
| `global:Invoke-TaskCleanup` | (Optional) Cleanup hook called after each task run |

> **Note:** All functions must use the `global:` scope prefix to be accessible from the task loader.

**Task function contracts:**
- `Get-TaskStatus` should return an object with `ToInstall`, `ToRemove`, and `UpToDate` arrays.
- `Invoke-TaskApply` should return an object with optional `installed` and `removed` arrays to update state.json.

---

## Path Resolution Rules

### Common Expansion

| Notation | Expands to |
|----------|------------|
| `~` | `C:\Users\<username>` |
| `%VARNAME%` | Environment variable expansion |

### Section-specific Rules

- `dotfiles.source` and `encrypted_files.source`:
  - If the path starts with `./` or `.\`, it is resolved relative to the directory containing the config file.
  - Otherwise it uses `~` and `%VARNAME%` expansion.
- `dotfiles.target`, `encrypted_files.target`, `age.key_file`:
  - Use `~` and `%VARNAME%` expansion only. Relative paths are resolved from the current working directory.
- `environment.path` entries:
  - In addition to `~`/`%VARNAME%`, these shorthands are normalized:
    - `$HOME` → `%USERPROFILE%`
    - `$env:VARNAME` → `%VARNAME%`
    - `$VARNAME` → `%VARNAME%` (common Windows env vars like `APPDATA`, `LOCALAPPDATA`, etc.)
