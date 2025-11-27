#!/usr/bin/env bash
#
# fish/install.sh
#
# Installs fish shell and fisher plugin manager
# Supports --dry-run mode via DRY_RUN environment variable.

set -e

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DOTFILES_ROOT/script/lib.sh"

# Install fisher if not present
install_fisher() {
    if fish -c "type -q fisher" 2>/dev/null; then
        verbose "Fisher already installed"
        return 0
    fi

    info "Installing fisher..."
    run fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"
    [[ "$DRY_RUN" == true ]] || success "Fisher installed"
}

# Install plugins from fish_plugins
install_plugins() {
    local plugins_file="$HOME/.config/fish/fish_plugins"
    if [[ -f "$plugins_file" ]]; then
        info "Installing fish plugins..."
        run fish -c "fisher update"
        [[ "$DRY_RUN" == true ]] || success "Fish plugins installed"
    else
        verbose "No fish_plugins file found"
    fi
}

# Set fish as default shell
set_default_shell() {
    local fish_path
    fish_path="$(which fish)"

    if [[ "$SHELL" == "$fish_path" ]]; then
        verbose "Fish is already default shell"
        return 0
    fi

    if ! grep -q "$fish_path" /etc/shells; then
        warn_non_idempotent "Modifying /etc/shells (requires sudo)"
        info "Adding $fish_path to /etc/shells..."
        if [[ "$DRY_RUN" == true ]]; then
            printf "${GRAY}  [dry-run]${NC} echo %q | sudo tee -a /etc/shells\n" "$fish_path"
            DRYRUN_CHANGES+=("echo '$fish_path' | sudo tee -a /etc/shells")
        else
            echo "$fish_path" | sudo tee -a /etc/shells
        fi
    fi

    if prompt_yes_no_safe "Set fish as default shell?"; then
        run chsh -s "$fish_path"
        [[ "$DRY_RUN" == true ]] || success "Fish set as default shell"
    fi
}

main() {
    if ! has_command fish; then
        warn "Fish not installed. Install via Homebrew (macos) or apt (linux) first."
        return 1
    fi

    install_fisher
    install_plugins
    set_default_shell
}

main "$@"
