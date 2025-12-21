# Mister Manager

A Holman-style dotfiles manager with topic folders, symlink management, and 1Password integration.

## Features

- **Topic-based organization** - Group related configs (git, fish, mail, etc.)
- **Smart symlinking** - `*.symlink` files and `config/` directories
- **Cross-platform** - macOS and Linux support
- **Dry-run mode** - Preview changes before applying
- **Idempotent** - Safe to run multiple times
- **Secrets management** - Multi-backend (1Password, pass, Bitwarden, gopass, secret-tool) with Keychain caching
- **Health checks** - `--doctor` mode for system diagnostics

## Structure

```
dotfiles/
├── script/                    # Core scripts
│   ├── bootstrap              # Main entry point
│   ├── symlink                # Creates symlinks
│   ├── takeover               # Adopts existing files into repo
│   ├── secrets                # Unified secrets retrieval
│   ├── secrets-setup          # Interactive secrets migration
│   ├── lib.sh                 # Shared functions
│   ├── sort-brewfile          # Sorts Brewfile, manages pending
│   └── brew-audit             # Find untracked Homebrew packages
├── test/                      # Smoke tests
│   └── smoke.sh
├── bin/                       # Custom scripts (→ ~/.bin)
├── editor/
│   └── config/helix/          # → ~/.config/helix
│       └── config.toml
├── fish/
│   ├── config/fish/           # → ~/.config/fish
│   │   ├── config.fish
│   │   ├── fish_plugins
│   │   ├── functions/
│   │   └── completions/       # Shell completions
│   └── install.sh
├── git/
│   └── gitconfig.symlink      # → ~/.gitconfig
├── macos/
│   ├── Brewfile.example       # Homebrew packages template
│   └── install.sh
├── linux/
│   ├── packages.txt           # Distro packages
│   └── install.sh
├── mail/
│   ├── config/aerc/           # → ~/.config/aerc
│   │   ├── aerc.conf
│   │   └── accounts.conf.template
│   ├── mbsyncrc.example       # mbsync config template
│   ├── notmuch-config.example # notmuch config template
│   └── install.sh
├── rust/
│   ├── packages.example.txt   # Cargo packages template
│   └── install.sh
├── ssh/
│   ├── example.ssh            # Example host definitions
│   └── install.sh             # Adds Include directive
├── system/
│   ├── profile.symlink        # → ~/.profile
│   └── zshrc.symlink          # → ~/.zshrc
├── terminal/
│   └── alacritty.toml.symlink # → ~/.alacritty.toml
└── tmux/
    ├── tmux.conf.symlink      # → ~/.tmux.conf
    └── install.sh
```

## Conventions

| Pattern | Result |
|---------|--------|
| `topic/foo.symlink` | → `~/.foo` |
| `topic/config/bar/` | → `~/.config/bar` |
| `topic/install.sh` | Runs during bootstrap |
| `bin/` | → `~/.bin` (added to PATH) |

---

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/you/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

### 2. Customize Your Config

Before running bootstrap, copy and customize the example files:

```bash
# Package lists
cp macos/Brewfile.example macos/Brewfile
cp rust/packages.example.txt rust/packages.txt

# Mail configuration (if using aerc/mbsync)
cp mail/mbsyncrc.example ~/.mbsyncrc
cp mail/notmuch-config.example ~/.notmuch-config

# Edit git config with your details
$EDITOR git/gitconfig.symlink
```

### 3. Install

```bash
# Standard install (symlinks + installers)
./script/bootstrap

# Full install for new machine (includes packages)
./script/bootstrap --full
```

---

## Command Reference

```
Usage: bootstrap [command] [options]

Commands:
  (default)          Install dotfiles (symlinks + installers)
  --unlink           Remove symlinks and restore backups
  --track [path]     Track symlinks (scan all if no path given)
  --doctor, --status Comprehensive system health check

Options:
  -n, --dry-run       Show what would be done without making changes
  -v, --verbose       Show verbose output (state checks, skipped operations)
  --no-install        Skip running install.sh scripts
  --symlinks-only     Only create symlinks, skip installers
  --with-packages     Install packages (Brewfile, distro packages, Rust crates)
  --with-keys         Copy SSH keys from 1Password to ~/.ssh
  --full              Complete install: symlinks + installers + packages + keys + secrets
  -h, --help          Show this help

Locking:
  Only one bootstrap instance can run at a time. Concurrent runs will fail
  with an error. Stale locks from crashed processes are auto-cleaned.
```

### Examples

```bash
# Standard install (symlinks + installers, no packages)
./script/bootstrap

# Full install for new machine
./script/bootstrap --full

# Preview what would happen
./script/bootstrap --full --dry-run
./script/bootstrap --dry-run -v        # With extra detail

# Selective installs
./script/bootstrap --with-packages     # Include Brewfile + Rust packages
./script/bootstrap --with-keys         # Include SSH keys from 1Password
./script/bootstrap --symlinks-only     # Only symlinks, no installers

# Manage links
./script/bootstrap --unlink            # Remove symlinks, restore backups
./script/bootstrap --track             # Scan and track all symlinks

# Health check
./script/bootstrap --doctor            # Check system health
```

---

## Customization

### Adding Your Own Config

1. **Create a topic folder**: `mkdir newtopic`
2. **Add symlink file**: `newtopic/foo.symlink` → `~/.foo`
3. **Or config dir**: `newtopic/config/bar/` → `~/.config/bar`
4. **Optional installer**: `newtopic/install.sh` for setup tasks

### Adopting Existing Config

Use `takeover` to move existing config files into the repo:

```bash
./script/takeover ~/.gitconfig git
./script/takeover ~/.config/fish fish --config
./script/takeover ~/.config/helix editor --config
```

### Adding Custom Scripts

Place scripts in `bin/` - they'll be symlinked to `~/.bin`:

```bash
# Create a script
cat > bin/my-script << 'EOF'
#!/usr/bin/env bash
echo "Hello from my script!"
EOF
chmod +x bin/my-script

# After bootstrap, it's available as:
my-script
```

---

## Secrets Management

Unified secrets management with multiple password manager backends and optional macOS Keychain caching.

### Supported Backends

| Backend | CLI | Reference Format | Install |
|---------|-----|------------------|---------|
| **1Password** | `op` | `op://Vault/Item/field` | `brew install 1password-cli` |
| **pass** | `pass` | `path/to/secret` | `brew install pass` |
| **Bitwarden** | `bw` | `item-name-or-uuid` | `brew install bitwarden-cli` |
| **gopass** | `gopass` | `path/to/secret` | `brew install gopass` |
| **secret-tool** | `secret-tool` | `attr1=val1,attr2=val2` | `apt install libsecret-tools` |

### Architecture

```
┌──────────────────┐
│  Config files    │  Use: PassCmd, source-cred-cmd, etc.
│  (mbsync, aerc)  │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ script/secrets   │  Unified secrets retrieval
└────────┬─────────┘
         │
    ┌────┴────────────────────┐
    ▼                         ▼
┌────────┐  ┌─────────────────────────────────────┐
│Keychain│  │ Backends: op, pass, bw, gopass, ... │
│ (cache)│  │         (source of truth)           │
└────────┘  └─────────────────────────────────────┘
```

### Setup

1. **Install your preferred password manager CLI** (see table above)

2. **Create `script/secrets.defs.local` with your secrets:**
   ```bash
   cp script/secrets.defs.example script/secrets.defs.local
   # Edit to add your secrets:
   SECRET_DEFS="
   # 1Password
   email/password|op://Personal/Email App Password/password

   # pass (password-store)
   github/token|pass:tokens/github

   # Bitwarden
   api/key|bw:api-credentials

   # gopass
   ssh/passphrase|gopass:ssh/id_ed25519

   # secret-tool (Linux keyring)
   db/password|secret-tool:service=mydb,user=admin
   "
   ```

3. **Check available backends:**
   ```bash
   ./script/secrets backends
   ```

4. **Validate secrets are accessible:**
   ```bash
   ./script/secrets validate
   ```

5. **Cache for offline use (macOS only):**
   ```bash
   ./script/secrets cache-all
   ```

### Usage

```bash
# Get a secret (tries Keychain cache first, then backend)
./script/secrets get email/password

# List available secrets with their backends
./script/secrets list

# Show which backends are installed
./script/secrets backends

# In config files (PassCmd, source-cred-cmd, etc.):
PassCmd "secrets get email/password"
```

### Backend-Specific Notes

**1Password (`op`):**
- Requires sign-in: `op signin`
- References use the `op://` URI format

**pass / gopass:**
- Uses GPG for encryption
- Store location: `~/.password-store` (pass) or `~/.local/share/gopass` (gopass)
- gopass is pass-compatible with team features

**Bitwarden (`bw`):**
- Requires session: `export BW_SESSION=$(bw unlock --raw)`
- Can use item name or UUID

**secret-tool (libsecret):**
- Integrates with GNOME Keyring / KDE Wallet
- Uses key-value attribute pairs for lookup

---

## SSH Config

SSH configuration uses the `Include` directive rather than symlinking `~/.ssh/config`.

### How it Works

The `ssh/install.sh` script adds this line to `~/.ssh/config`:

```bash
Include ~/.dotfiles/ssh/*.ssh
```

Create host definitions in `ssh/*.ssh` files:

```bash
# ssh/personal.ssh
Host myserver
    HostName server.example.com
    User myuser
    IdentityFile ~/.ssh/id_ed25519

# ssh/work.ssh
Host work-*
    User deploy
    IdentityFile ~/.ssh/work_key
```

Benefits:
- `~/.ssh/config` stays machine-local (not symlinked)
- Keys and known_hosts never touched
- Multiple context files (personal.ssh, work.ssh)
- No secrets in git

### SSH Keys from 1Password

Optionally store SSH keys in 1Password and copy during bootstrap:

```bash
./script/bootstrap --with-keys
```

Configure keys in `ssh/install.sh`:
```bash
SSH_KEYS="
id_ed25519|SSH Key - ED25519
id_rsa|SSH Key - RSA
"
```

---

## Mail Setup (aerc + mbsync + notmuch)

### Quick Start

1. Copy and configure example files:
   ```bash
   cp mail/mbsyncrc.example ~/.mbsyncrc
   cp mail/notmuch-config.example ~/.notmuch-config
   cp mail/config/aerc/accounts.conf.template ~/.config/aerc/accounts.conf
   # Edit each file with your account details
   ```

2. Add secrets for your email password:
   ```bash
   # Edit script/secrets to add your email secret
   # Then validate and cache:
   ./script/secrets validate
   ./script/secrets cache-all
   ```

3. Run mail installer:
   ```bash
   ./mail/install.sh
   ```

4. Sync mail:
   ```bash
   mbsync -a
   notmuch new
   aerc
   ```

---

## Cross-Platform

| Component | macOS | Linux |
|-----------|-------|-------|
| Packages | `brew bundle` (macos/Brewfile) | apt/dnf/pacman (linux/packages.txt) |
| Secrets | Keychain cache + any backend | Any supported backend |
| Shell | fish (Homebrew) | fish (package manager) |

The bootstrap script auto-detects OS and runs appropriate installers.

### Homebrew Packages (macOS)

Packages are defined in `macos/Brewfile`. Use standard Homebrew Bundle commands:

```bash
brew bundle install --file=macos/Brewfile   # Install all packages
brew bundle check --file=macos/Brewfile     # Check what's missing
brew bundle cleanup --file=macos/Brewfile   # Remove unlisted packages
```

#### Auditing Installed Packages

Find packages you've installed but haven't added to your Brewfile:

```bash
./script/brew-audit              # Interactive (uses fzf if available)
./script/brew-audit --dry-run    # Preview without changes
./script/brew-audit --no-fzf     # Use simple y/n prompts
```

With fzf: Use Tab to select packages to add, Enter to confirm.
Unselected packages go to `Brewfile.pending` and won't be prompted again.

#### Sorting and Pending

```bash
./script/sort-brewfile           # Sort Brewfile alphabetically
./script/sort-brewfile --dry-run # Preview changes
```

- Commented-out entries in Brewfile move to `Brewfile.pending`
- Uncommented entries in pending restore to Brewfile
- Inline comments (e.g., `brew "bat" # syntax highlighting`) are preserved

### Linux Packages

Edit `linux/packages.txt` with distro-specific mappings:

```bash
# Simple package name (same on all distros)
fish
tmux
git

# Distro-specific mapping
debian:fd-find,fedora:fd-find,arch:fd
debian:build-essential,fedora:@development-tools,arch:base-devel
```

---

## Testing

Run smoke tests to verify scripts work correctly:

```bash
./test/smoke.sh           # Run all tests
./test/smoke.sh -v        # Verbose output
```

Tests include:
- Syntax validation for all bash scripts
- Help flag functionality
- Dry-run mode operation
- Doctor/status command
- Fish completion syntax
- Idempotency checks

---

## Logging

All operations are logged to `~/.local/state/dotfiles/dotfiles.log` (follows [XDG Base Directory spec](https://specifications.freedesktop.org/basedir-spec/latest/)).

Log format:
```
2025-01-15T10:30:00Z INFO  === Session start: ./script/bootstrap --full ===
2025-01-15T10:30:00Z INFO  --- Symlinks ---
2025-01-15T10:30:01Z INFO  Creating symlink: ~/.gitconfig
2025-01-15T10:30:02Z WARN  File already exists, backing up
2025-01-15T10:30:03Z ERROR Failed to create symlink
2025-01-15T10:30:04Z DEBUG Verbose details (with -v flag)
```

```bash
# View recent logs
tail -50 ~/.local/state/dotfiles/dotfiles.log

# Or if you've set XDG_STATE_HOME:
tail -50 "$XDG_STATE_HOME/dotfiles/dotfiles.log"

# Disable logging
DOTFILES_LOG=none ./script/bootstrap

# Custom log location
DOTFILES_LOG=/tmp/dotfiles.log ./script/bootstrap
```

### Locking

Bootstrap uses a lockfile to prevent concurrent runs:

```bash
# If you try to run bootstrap while another instance is running:
./script/bootstrap
# ✗ Bootstrap already running (PID: 12345, lockdir: /tmp/dotfiles-bootstrap.lock)
```

- **Location**: `$TMPDIR/dotfiles-bootstrap.lock` (or `/tmp/` on Linux)
- **Stale locks**: Automatically cleaned if the owning process has died
- **Release**: Lock is released automatically when bootstrap exits (including crashes)

The locking mechanism:
1. Creates a lock directory (atomic operation on all filesystems)
2. Writes the current PID to a file inside the lock directory
3. On subsequent runs, checks if the PID in the lock is still alive
4. If the process is dead, cleans up the stale lock and proceeds
5. Uses a trap to ensure the lock is released on exit, even on errors

---

## Local Overrides

These files are gitignored and loaded if present:

| File | Purpose |
|------|---------|
| `~/.gitconfig.local` | Machine-specific git config (name, email, signing) |
| `~/.config/fish/secrets.fish` | Manual secret overrides |
| `~/.config/aerc/accounts.conf` | Mail accounts (from template) |
| `~/.ssh/config` | Machine-local SSH config (includes dotfiles hosts) |

---

## Forking This Template

When you fork this repository for personal use:

### Files That Stay Personal

These files contain your personal config and won't merge from upstream:
- `fish/config/fish/config.fish` - Your shell environment
- `fish/config/fish/conf.d/*` - Your shell snippets
- `mail/config/aerc/accounts.conf.template` - Your email accounts
- `mail/install.sh` - Your mail provider settings
- `README.md` - Your personal documentation

### Files That Merge From Upstream

These template files will receive upstream improvements:
- `script/secrets` - Core secrets logic (your defs are in `secrets.defs.local`)
- `script/sort-brewfile` - Brewfile sorting
- `script/bootstrap` - Main installer
- `script/lib.sh` - Shared functions
- All `*.example` files

### Setting Up Merge Strategy

After forking, run:
```bash
git config --local merge.ours.driver true
```

This enables the `.gitattributes` merge strategies that keep personal files from being overwritten.

### Updating From Upstream

```bash
git remote add upstream https://github.com/OWNER/mister-manager.git
git fetch upstream
git merge upstream/main
# Personal files auto-resolve to yours via .gitattributes
# Review any remaining conflicts in template files
```

---

## License

MIT
