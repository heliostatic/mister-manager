#!/usr/bin/env bash
#
# tmux/install.sh
#
# Installs tmux plugin manager (TPM)
# Supports --dry-run mode via DRY_RUN environment variable.

set -e

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DOTFILES_ROOT/script/lib.sh"

TPM_DIR="$HOME/.tmux/plugins/tpm"

install_tpm() {
    if [[ -d "$TPM_DIR" ]]; then
        verbose "TPM already installed at $TPM_DIR"
        return 0
    fi

    info "Installing TPM (Tmux Plugin Manager)..."
    ensure_dir "$HOME/.tmux/plugins"
    run git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
    [[ "$DRY_RUN" == true ]] || success "TPM installed"
}

install_plugins() {
    if [[ "$DRY_RUN" == true ]]; then
        if [[ -d "$TPM_DIR" ]] || would_change dir "$TPM_DIR"; then
            info "Installing tmux plugins..."
            printf "${GRAY}  [dry-run]${NC} %s/bin/install_plugins\n" "$TPM_DIR"
            DRYRUN_CHANGES+=("$TPM_DIR/bin/install_plugins")
        fi
        return 0
    fi

    if [[ -d "$TPM_DIR" ]]; then
        info "Installing tmux plugins..."
        "$TPM_DIR/bin/install_plugins" || true
        success "Tmux plugins installed"
    fi
}

main() {
    if ! has_command tmux; then
        warn "tmux not installed"
        return 1
    fi

    install_tpm
    install_plugins
}

main "$@"
