#!/usr/bin/env bash
#
# ssh/install.sh
#
# Sets up SSH config to include dotfiles-managed host definitions.
# Uses SSH's Include directive rather than symlinking ~/.ssh/config.
#
# Optionally copies SSH keys from 1Password when WITH_SSH_KEYS=true
# (delegates to script/secrets keys).
#
# Supports --dry-run mode via DRY_RUN environment variable.

set -e

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DOTFILES_ROOT/script/lib.sh"

SSH_DIR="$HOME/.ssh"
SSH_CONFIG="$SSH_DIR/config"
INCLUDE_LINE="Include $DOTFILES_ROOT/ssh/*.ssh"

setup_ssh_include() {
    # Ensure ~/.ssh exists with correct permissions
    if [[ ! -d "$SSH_DIR" ]]; then
        info "Creating $SSH_DIR..."
        run mkdir -p "$SSH_DIR"
        run chmod 700 "$SSH_DIR"
    else
        verbose "SSH directory exists: $SSH_DIR"
    fi

    # Check if config exists and already has our include
    if [[ -f "$SSH_CONFIG" ]]; then
        if grep -qF "$INCLUDE_LINE" "$SSH_CONFIG" 2>/dev/null; then
            verbose "Include line already present in $SSH_CONFIG"
            return 0
        fi

        # Config exists but doesn't have our include - prepend it
        info "Adding Include directive to $SSH_CONFIG..."
        if [[ "$DRY_RUN" == true ]]; then
            printf "${GRAY}  [dry-run]${NC} Prepend Include line to %s\n" "$SSH_CONFIG"
            _dryrun_count
        else
            # Create temp file with include line + existing content
            {
                echo "$INCLUDE_LINE"
                echo ""
                cat "$SSH_CONFIG"
            } > "$SSH_CONFIG.tmp"
            mv "$SSH_CONFIG.tmp" "$SSH_CONFIG"
            success "Added Include directive to SSH config"
        fi
    else
        # No config exists - create one with just the include
        info "Creating $SSH_CONFIG with Include directive..."
        if [[ "$DRY_RUN" == true ]]; then
            printf "${GRAY}  [dry-run]${NC} Create %s with Include line\n" "$SSH_CONFIG"
            _dryrun_count
        else
            echo "$INCLUDE_LINE" > "$SSH_CONFIG"
            chmod 600 "$SSH_CONFIG"
            success "Created SSH config with Include directive"
        fi
    fi
}

show_ssh_files() {
    local ssh_files
    ssh_files=$(find "$DOTFILES_ROOT/ssh" -name "*.ssh" 2>/dev/null || true)

    if [[ -n "$ssh_files" ]]; then
        verbose "SSH config files that will be included:"
        echo "$ssh_files" | while read -r f; do
            verbose "  - $(basename "$f")"
        done
    else
        info "No *.ssh files found in $DOTFILES_ROOT/ssh/"
        info "Create files like 'personal.ssh' or 'work.ssh' with your Host definitions"
    fi
}

setup_ssh_keys() {
    # Only run if --with-keys was passed to bootstrap
    if [[ "$WITH_SSH_KEYS" != true ]]; then
        verbose "Skipping SSH key setup (use --with-keys to enable)"
        return 0
    fi

    # Delegate to secrets script (handles 1Password, dry-run, etc.)
    local args=()
    [[ "$DRY_RUN" == true ]] && args+=("--dry-run")
    [[ "$NO_SUMMARY" == true ]] && args+=("--no-summary")

    "$DOTFILES_ROOT/script/secrets" keys "${args[@]}"
}

main() {
    setup_ssh_include
    show_ssh_files
    setup_ssh_keys
}

main "$@"
