#!/usr/bin/env bash
#
# rust/install.sh
#
# Installs rustup/cargo if missing.
# Optionally installs packages from packages.txt when WITH_RUST_PACKAGES=true.

set -e

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DOTFILES_ROOT/script/lib.sh"

PACKAGES_FILE="$DOTFILES_ROOT/rust/packages.txt"

install_rustup() {
    if has_command rustup; then
        verbose "rustup already installed"
        return 0
    fi

    info "Installing rustup..."
    if [[ "$DRY_RUN" == true ]]; then
        printf "${GRAY}  [dry-run]${NC} curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y\n"
        _dryrun_count
    else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        # Source cargo env for this session
        source "$HOME/.cargo/env"
        success "Installed rustup"
    fi
}

install_packages() {
    if [[ "$WITH_PACKAGES" != true ]]; then
        verbose "Skipping Rust packages (use --with-packages or --full)"
        return 0
    fi

    if [[ ! -f "$PACKAGES_FILE" ]]; then
        warn "No packages.txt found at $PACKAGES_FILE"
        return 0
    fi

    info "Installing Rust packages..."

    # Ensure cargo is available
    if [[ -f "$HOME/.cargo/env" ]]; then
        source "$HOME/.cargo/env"
    fi

    if ! has_command cargo; then
        warn "cargo not found - cannot install packages"
        return 1
    fi

    # Get list of installed packages for skip check
    local installed=""
    if [[ "$DRY_RUN" != true ]]; then
        installed=$(cargo install --list 2>/dev/null | grep -E '^[a-zA-Z]' | awk '{print $1}' | tr -d ':')
    fi

    local count=0
    local skipped=0

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue

        # Parse package name (before @ or space)
        local pkg_name="${line%%@*}"
        pkg_name="${pkg_name%% *}"

        # Check if already installed
        if echo "$installed" | grep -qx "$pkg_name" 2>/dev/null; then
            verbose "Already installed: $pkg_name"
            ((skipped++)) || true
            continue
        fi

        if [[ "$DRY_RUN" == true ]]; then
            printf "${GRAY}  [dry-run]${NC} cargo install %s\n" "$line"
            _dryrun_count
            ((count++)) || true
        else
            info "Installing: $pkg_name"
            if cargo install $line; then
                success "Installed: $pkg_name"
                ((count++)) || true
            else
                warn "Failed to install: $pkg_name"
            fi
        fi
    done < "$PACKAGES_FILE"

    if [[ "$DRY_RUN" == true ]]; then
        info "Would install $count package(s), skip $skipped already installed"
    else
        success "Installed $count package(s), skipped $skipped already installed"
    fi
}

main() {
    install_rustup
    install_packages
}

main "$@"
