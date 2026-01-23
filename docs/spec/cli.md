# CLI Command Reference

## Command List

```
winix apply                          # Apply configuration
winix status                         # Show current state and differences
winix --help                         # Show help
winix --version                      # Show version

winix secret keygen [<path>]         # Generate age key pair
winix secret encrypt <file>          # Encrypt file
winix secret decrypt <file>          # Decrypt file

winix config encrypt [--remove]      # Encrypt winix.yaml to winix.yaml.age
winix config decrypt [--force]       # Decrypt winix.yaml.age to winix.yaml
winix config cache-clear             # Clear decrypted config cache
```

---

## Basic Commands

### winix apply

Sync environment based on configuration file (winix.yaml).

```powershell
winix apply              # Apply configuration
```

### winix status

Show differences between current environment and configuration file.
This is the **only preview mode** (apply has no dry-run option).
It uses the same execution path as apply with DryRun, so Scoop/Winget are required
when their sections are configured and changes are detected.

```powershell
winix status
```

**Example output:**

```
==== WINIX STATUS ====
Previewing changes (no changes will be made).

-- Packages / Scoop --
[01/02]  + nodejs             (would install)
[02/02]  - vim                (would remove)

-- Dotfiles --
  + ~/.config/starship.toml    (would add)
  ~ ~/.gitconfig               (would update)

-- Environment --
  + EDITOR=nvim    (would add, user)

Run 'winix apply' to apply changes.
```

### winix --help / winix --version

```powershell
winix --help      # Show help
winix --version   # Show version
winix -h          # Short option for --help
winix -v          # Short option for --version
```

---

## Secrets Management Commands

### winix secret keygen

Generate age key pair.

```powershell
winix secret keygen                        # Default path
winix secret keygen ~/.config/winix/key.txt  # Specify path
```

**Output:**

```
Key generated at: ~/.config/winix/key.txt
Public key: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### winix secret encrypt

Encrypt file with age. Requires `age.public_key` in winix.yaml.

```powershell
winix secret encrypt ./secrets/credentials.json
```

**Output:** Creates `./secrets/credentials.json.age`

### winix secret decrypt

Decrypt encrypted file and display to stdout.

**Prerequisites:** `age.bitwarden_item` or `age.key_file` must be configured in winix.yaml, or provide key via environment variables.

```powershell
winix secret decrypt ./secrets/credentials.json.age
```

---

## Config Management Commands

### winix config encrypt

Encrypt `winix.yaml` to `winix.yaml.age` using the public key from the age section.

```powershell
winix config encrypt           # Encrypt config, keep original
winix config encrypt --remove  # Encrypt config and remove original
```

**Options:**

| Option | Description |
|--------|-------------|
| `--remove` | Remove the original `winix.yaml` after encryption |

**Prerequisites:** `age.public_key` must be configured in winix.yaml.

### winix config decrypt

Decrypt `winix.yaml.age` to `winix.yaml` for editing.

```powershell
winix config decrypt           # Decrypt config (fails if winix.yaml exists)
winix config decrypt --force   # Decrypt config, overwrite existing
```

**Options:**

| Option | Description |
|--------|-------------|
| `--force` | Overwrite existing `winix.yaml` if it exists |

**Prerequisites:** One of the following environment variables must be set:
- `WINIX_AGE_KEY`: The age secret key directly
- `WINIX_AGE_KEY_FILE`: Path to file containing the age secret key
- `WINIX_BITWARDEN_ITEM`: Bitwarden item name containing the age key

**Typical workflow:**

```powershell
# Decrypt for editing
winix config decrypt

# Edit the config
notepad winix.yaml

# Re-encrypt (optionally remove plain file)
winix config encrypt --remove
```

### winix config cache-clear

Clear the decrypted config cache, forcing re-decryption on next run.

```powershell
winix config cache-clear
```

**Use case:** When you've updated `winix.yaml.age` externally and want to force re-decryption.

---

## Encrypted Config Support

winix supports encrypted configuration files (`winix.yaml.age`). When `winix.yaml` is not found, winix automatically looks for `winix.yaml.age` and decrypts it.

### Environment Variables for Decryption

Set one of these environment variables to provide the age secret key:

| Variable | Description |
|----------|-------------|
| `WINIX_AGE_KEY` | The age secret key directly (e.g., `AGE-SECRET-KEY-1...`) |
| `WINIX_AGE_KEY_FILE` | Path to a file containing the age secret key |
| `WINIX_BITWARDEN_ITEM` | Bitwarden item name containing the age key |

**Priority:** `WINIX_AGE_KEY` > `WINIX_AGE_KEY_FILE` > `WINIX_BITWARDEN_ITEM`

### Caching

Decrypted config is cached at `~/.config/winix/cache/config.yaml`. The cache is automatically invalidated when the source `.age` file changes (detected via SHA256 hash comparison).

### Example Usage

```powershell
# Encrypt your config
winix config encrypt --remove

# Set the environment variable for decryption
$env:WINIX_BITWARDEN_ITEM = "winix-age-key"

# Now winix will automatically decrypt and use the config
winix status
winix apply
```

---

## Output Format

### Symbol Meanings

| Symbol | Meaning | Color |
|--------|---------|-------|
| `+` | Add | Green |
| `-` | Remove | Red |
| `~` | Change | Yellow |
| `=` | Start tracking existing item (dotfiles or PATH) | Yellow/DarkGray |

### Output Structure

- Each run prints a banner (e.g., `==== WINIX APPLY ====`, `==== WINIX STATUS ====`).
- Sections are shown as `-- <Section Name> --`.
- Package sections use a progress prefix like `[01/05]`.

### apply Output Example

```
==== WINIX APPLY ====
Applying changes...

-- Packages / Scoop --
[01/02]  + nodejs             done
[02/02]  - vim                done

-- Dotfiles --
  + ~/.config/starship.toml    done
  ~ ~/.gitconfig               done

-- Environment --
  + EDITOR=nvim    done

Applied 5 changes.
```

### status Output Example

```
==== WINIX STATUS ====
Previewing changes (no changes will be made).

-- Packages / Scoop --
[01/02]  + nodejs             (would install)
[02/02]  - vim                (would remove)

-- Dotfiles --
  ~ ~/.gitconfig

Run 'winix apply' to apply changes.
```

---

## Error Handling

### Invalid Command

```
Error: Unknown command 'foo'. Run 'winix --help' for usage.
```

Exit code: 1

