#!/usr/bin/env bash
#
# mail/install.sh
#
# Sets up mail environment: maildir, address book
# Supports --dry-run mode via DRY_RUN environment variable.
#
# Configuration:
#   Set MAIL_ACCOUNT_NAME to customize the maildir name (default: "Mail")
#   Set MAIL_EMAIL to your email address for keychain setup

set -e

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DOTFILES_ROOT/script/lib.sh"

# Configurable defaults (override in your environment or local config)
MAIL_ACCOUNT_NAME="${MAIL_ACCOUNT_NAME:-Mail}"
MAIL_EMAIL="${MAIL_EMAIL:-}"

setup_maildir() {
    local maildir="$HOME/.maildir/$MAIL_ACCOUNT_NAME"

    if [[ -d "$maildir" ]]; then
        verbose "Maildir already exists at $maildir"
        return 0
    fi

    info "Creating maildir at $maildir..."
    ensure_dir "$maildir/Inbox"
    ensure_dir "$maildir/Sent"
    ensure_dir "$maildir/Drafts"
    ensure_dir "$maildir/Trash"
    ensure_dir "$maildir/Archive"
    [[ "$DRY_RUN" == true ]] || success "Maildir created"
}

setup_mbsync_password() {
    local keychain_service="mbsync-${MAIL_ACCOUNT_NAME,,}"  # lowercase

    # Check if password is already in keychain
    if security find-generic-password -s "$keychain_service" &>/dev/null; then
        verbose "mbsync password already in keychain"
        return 0
    fi

    if [[ -z "$MAIL_EMAIL" ]]; then
        info "Set MAIL_EMAIL environment variable to enable keychain password setup"
        return 0
    fi

    echo ""
    warn "mbsync needs your email app password stored in macOS Keychain"
    echo ""
    echo "To set up:"
    echo "  1. Create an app password with your email provider"
    echo "  2. Run: security add-generic-password -s '$keychain_service' -a '$MAIL_EMAIL' -w"
    echo "     (it will prompt for the password)"
    echo ""

    if prompt_yes_no_safe "Add password to keychain now?"; then
        warn_non_idempotent "Adding password to keychain (interactive)"
        run security add-generic-password -s "$keychain_service" -a "$MAIL_EMAIL" -w
        [[ "$DRY_RUN" == true ]] || success "Password added to keychain"
    fi
}

setup_address_book() {
    local addr_book="$HOME/.address_book"

    if [[ -f "$addr_book" ]]; then
        verbose "Address book already exists at $addr_book"
        return 0
    fi

    info "Creating empty address book at $addr_book..."
    if [[ "$DRY_RUN" == true ]]; then
        printf "${GRAY}  [dry-run]${NC} Create %s with header comments\n" "$addr_book"
        DRYRUN_CHANGES+=("Create $addr_book")
    else
        touch "$addr_book"
        echo "# Address book for aerc" >> "$addr_book"
        echo "# Format: email<TAB>name" >> "$addr_book"
        success "Address book created"
    fi
}

main() {
    setup_maildir
    setup_address_book

    if [[ "$(get_os)" == "macos" ]]; then
        setup_mbsync_password
    else
        info "On Linux, configure PassCmd in ~/.mbsyncrc to use pass or secret-tool"
    fi
}

main "$@"
