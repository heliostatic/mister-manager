#!/usr/bin/env bash
#
# git/install.sh
#
# Git-specific setup:
#   - Symlinks git hooks from git/hooks/ to .git/hooks/
#
# Supports --dry-run mode via DRY_RUN environment variable.

set -e

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DOTFILES_ROOT/script/lib.sh"

setup_hooks() {
    local git_dir="$DOTFILES_ROOT/.git"
    local hooks_src="$DOTFILES_ROOT/git/hooks"
    local hooks_dst="$git_dir/hooks"

    # Only run if we're in a git repo
    if [[ ! -d "$git_dir" ]]; then
        verbose "Not a git repository, skipping hooks setup"
        return 0
    fi

    if [[ ! -d "$hooks_src" ]]; then
        verbose "No hooks directory at $hooks_src"
        return 0
    fi

    info "Setting up git hooks..."

    for hook in "$hooks_src"/*; do
        [[ -f "$hook" ]] || continue

        local hook_name
        hook_name=$(basename "$hook")
        local dst="$hooks_dst/$hook_name"

        # Check if already linked correctly
        if [[ -L "$dst" ]] && [[ "$(readlink "$dst")" == "$hook" ]]; then
            verbose "Hook already linked: $hook_name"
            continue
        fi

        # Backup existing hook if present
        if [[ -e "$dst" && ! -L "$dst" ]]; then
            local backup="$dst.backup.$(date +%Y%m%d-%H%M%S)"
            warn "Backing up existing hook: $hook_name → $backup"
            run mv "$dst" "$backup"
        elif [[ -L "$dst" ]]; then
            run rm "$dst"
        fi

        run ln -s "$hook" "$dst"
        [[ "$DRY_RUN" == true ]] || success "Linked hook: $hook_name"
    done
}

main() {
    setup_hooks
}

main "$@"
