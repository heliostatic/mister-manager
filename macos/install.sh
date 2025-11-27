#!/usr/bin/env bash
#
# macos/install.sh
#
# macOS-specific setup: Homebrew and Brewfile
# Supports --dry-run mode via DRY_RUN environment variable.

set -e

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DOTFILES_ROOT/script/lib.sh"

install_homebrew() {
    if has_command brew; then
        verbose "Homebrew already installed"
        return 0
    fi

    warn_non_idempotent "Homebrew installation (interactive installer)"
    info "Installing Homebrew..."

    if [[ "$DRY_RUN" == true ]]; then
        printf "${GRAY}  [dry-run]${NC} /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"\n"
        DRYRUN_CHANGES+=("Install Homebrew")
        return 0
    fi

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add to path for this session
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    success "Homebrew installed"
}

install_brewfile() {
    if [[ "$WITH_PACKAGES" != true ]]; then
        verbose "Skipping Brewfile packages (use --with-packages or --full)"
        return 0
    fi

    local brewfile="$DOTFILES_ROOT/macos/Brewfile"

    if [[ ! -f "$brewfile" ]]; then
        warn "No Brewfile found at $brewfile"
        return 0
    fi

    info "Installing Brewfile packages..."

    if [[ "$DRY_RUN" == true ]]; then
        printf "${GRAY}  [dry-run]${NC} brew bundle install --file=%q\n" "$brewfile"
        _dryrun_count
        # Show what would be installed
        if has_command brew; then
            if brew bundle check --file="$brewfile" &>/dev/null; then
                verbose "All Brewfile dependencies satisfied"
            else
                # List missing packages (requires --verbose)
                brew bundle check --file="$brewfile" --verbose 2>/dev/null | grep "^→" | while read -r line; do
                    printf "${GRAY}    %s${NC}\n" "$line"
                done
            fi
        fi
        return 0
    fi

    brew bundle install --file="$brewfile"
    success "Brewfile packages installed"
}

setup_macos_defaults() {
    # Uncomment and add macOS defaults you want to set
    # When adding defaults, use run() wrapper:
    #   run defaults write com.apple.finder AppleShowAllFiles -bool true
    # And mark non-idempotent operations:
    #   warn_non_idempotent "Killing Finder/Dock to apply changes"
    :
}

main() {
    if [[ "$(get_os)" != "macos" ]]; then
        verbose "Not on macOS, skipping macos installer"
        return 0
    fi

    install_homebrew
    install_brewfile
    setup_macos_defaults
}

main "$@"
