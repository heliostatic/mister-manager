#!/usr/bin/env bash
#
# lib.sh
#
# Shared functions for dotfiles scripts.
#
# Provides:
#   - Output functions: info, success, warn, fail, verbose, section
#   - Execution wrapper: run() - handles dry-run mode
#   - System detection: get_os, get_distro, has_command
#   - Idempotent helpers: ensure_dir, ensure_symlink, would_change
#   - Link tracking: track_link, untrack_link, find_repo_symlinks
#   - Logging: init_logging, logs to $XDG_STATE_HOME/dotfiles/
#   - Locking: acquire_lock, release_lock - prevent concurrent runs
#
# Environment variables:
#   DRY_RUN=true      Preview mode, no changes made
#   VERBOSE=true      Show extra detail
#   DOTFILES_LOG=none Disable logging (default: ~/.local/state/dotfiles/dotfiles.log)

# =============================================================================
# Logging
# =============================================================================
# Set DOTFILES_LOG to a file path to enable logging, or "none" to disable
# Default location follows XDG Base Directory spec (works on macOS and Linux)
_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
DOTFILES_LOG="${DOTFILES_LOG:-$_STATE_HOME/dotfiles/dotfiles.log}"
LOGGING_ENABLED=false

# Initialize logging - call from main script
init_logging() {
    if [[ -n "$DOTFILES_LOG" && "$DOTFILES_LOG" != "none" ]]; then
        # Ensure log directory exists
        local log_dir
        log_dir="$(dirname "$DOTFILES_LOG")"
        [[ -d "$log_dir" ]] || mkdir -p "$log_dir"

        LOGGING_ENABLED=true
        {
            echo ""
            echo "========================================"
            echo "[$(date -Iseconds)] Session start: $0 $*"
            echo "========================================"
        } >> "$DOTFILES_LOG"
    fi
}

# Log a message to file (internal use)
_log() {
    if [[ "$LOGGING_ENABLED" == true ]]; then
        echo "[$(date -Iseconds)] $*" >> "$DOTFILES_LOG"
    fi
}

# =============================================================================
# Process Locking
# =============================================================================
LOCKDIR="${TMPDIR:-/tmp}/dotfiles-bootstrap.lock"

# Acquire exclusive lock - prevents concurrent bootstrap runs
acquire_lock() {
    if mkdir "$LOCKDIR" 2>/dev/null; then
        # Successfully acquired lock
        echo $$ > "$LOCKDIR/pid"
        trap 'release_lock' EXIT
        return 0
    fi

    # Lock exists - check if stale (owner process dead)
    local pid
    pid=$(cat "$LOCKDIR/pid" 2>/dev/null)

    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
        # Stale lock - previous process died
        warn "Removing stale lock from PID $pid"
        rm -rf "$LOCKDIR"
        if mkdir "$LOCKDIR" 2>/dev/null; then
            echo $$ > "$LOCKDIR/pid"
            trap 'release_lock' EXIT
            return 0
        fi
    fi

    # Lock is held by running process
    fail "Bootstrap already running (PID: ${pid:-unknown}, lockdir: $LOCKDIR)"
}

# Release lock - called automatically on exit via trap
release_lock() {
    rm -rf "$LOCKDIR" 2>/dev/null || true
}

# =============================================================================
# Colors
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# =============================================================================
# Dry-run and Verbose modes (inherited from environment or set by caller)
# =============================================================================
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
export DRY_RUN VERBOSE

# Track changes for summary (use temp file for cross-process counting)
DRYRUN_CHANGES=()
# Use parent PID if set, otherwise use current PID (for main process)
DRYRUN_COUNT_FILE="${DRYRUN_COUNT_FILE:-${TMPDIR:-/tmp}/dotfiles-dryrun-count.$$}"
export DRYRUN_COUNT_FILE

# Increment dry-run counter (works across subshells)
_dryrun_count() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "1" >> "$DRYRUN_COUNT_FILE"
    fi
}

# =============================================================================
# Output Functions
# =============================================================================
info() {
    printf "${BLUE}▸${NC} %s\n" "$1"
    _log "INFO: $1"
}

# Section header for major phases
section() {
    echo ""
    printf "${BLUE}━━━${NC} %s ${BLUE}━━━${NC}\n" "$1"
    echo ""
    _log "SECTION: $1"
}

success() {
    printf "${GREEN}✓${NC} %s\n" "$1"
    _log "SUCCESS: $1"
}

warn() {
    printf "${YELLOW}⚠${NC} %s\n" "$1"
    _log "WARN: $1"
}

fail() {
    printf "${RED}✗${NC} %s\n" "$1"
    _log "FAIL: $1"
    exit 1
}

# Verbose-only output
verbose() {
    [[ "$VERBOSE" == true ]] || return 0
    printf "${GRAY}  │ %s${NC}\n" "$1"
    _log "VERBOSE: $1"
}

# =============================================================================
# Core Wrapper - ALL destructive operations go through this
# =============================================================================
run() {
    local cmd_str
    printf -v cmd_str '%q ' "$@"

    if [[ "$DRY_RUN" == true ]]; then
        printf "${GRAY}  [dry-run]${NC} %s\n" "$cmd_str"
        DRYRUN_CHANGES+=("$cmd_str")
        _dryrun_count
        return 0
    else
        [[ "$VERBOSE" == true ]] && printf "${GRAY}  [exec]${NC} %s\n" "$cmd_str"
        "$@"
    fi
}

# =============================================================================
# Prompt Functions
# =============================================================================
prompt() {
    local question="$1"
    local default="$2"
    local response

    printf "${YELLOW}?${NC} %s " "$question"
    read -r response
    echo "${response:-$default}"
}

prompt_yes_no() {
    local question="$1"
    local default="${2:-n}"
    local response

    if [[ "$default" == "y" ]]; then
        printf "${YELLOW}?${NC} %s [Y/n] " "$question"
    else
        printf "${YELLOW}?${NC} %s [y/N] " "$question"
    fi

    read -r response
    response="${response:-$default}"

    [[ "$response" =~ ^[Yy] ]]
}

# Prompt wrapper - shows intent in dry-run, actually prompts otherwise
prompt_yes_no_safe() {
    local question="$1"
    local default="${2:-n}"

    if [[ "$DRY_RUN" == true ]]; then
        printf "${GRAY}  [would prompt]${NC} %s [y/n]\n" "$question"
        return 1  # Assume "no" in dry-run
    fi

    prompt_yes_no "$question" "$default"
}

# =============================================================================
# System Detection
# =============================================================================
get_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        *)      echo "unknown" ;;
    esac
}

get_distro() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "${ID:-unknown}"
    else
        echo "unknown"
    fi
}

has_command() {
    command -v "$1" &>/dev/null
}

# =============================================================================
# Idempotency Helpers
# =============================================================================

# Idempotent directory creation
ensure_dir() {
    if [[ -d "$1" ]]; then
        verbose "Directory exists: $1"
        return 0
    fi
    run mkdir -p "$1"
}

# Idempotent symlink - only acts if needed
# Also tracks the link in .links file
ensure_symlink() {
    local src="$1"
    local dst="$2"

    # Check if symlink already points to correct target
    if [[ -L "$dst" ]]; then
        local current_target
        current_target="$(readlink "$dst")"
        if [[ "$current_target" == "$src" ]]; then
            verbose "Already linked: $dst → $src"
            # Ensure it's tracked even if already linked
            track_link "$src" "$dst"
            return 0
        else
            verbose "Symlink exists but points to: $current_target"
            run rm "$dst"
        fi
    elif [[ -e "$dst" ]]; then
        # Regular file/dir exists - back it up
        local backup="$dst.backup.$(date +%Y%m%d-%H%M%S)"
        warn "Backing up existing: $dst → $backup"
        run mv "$dst" "$backup"
    fi

    run ln -s "$src" "$dst"
    track_link "$src" "$dst"
    [[ "$DRY_RUN" == true ]] || success "Linked: $dst → $src"
}

# Check if operation would change anything
would_change() {
    local check_type="$1"
    shift

    case "$check_type" in
        symlink)
            local src="$1" dst="$2"
            if [[ -L "$dst" ]] && [[ "$(readlink "$dst")" == "$src" ]]; then
                return 1  # No change needed
            fi
            return 0  # Change needed
            ;;
        dir)
            [[ ! -d "$1" ]]
            ;;
        file)
            [[ ! -f "$1" ]]
            ;;
        *)
            return 0  # Assume change needed if unknown
            ;;
    esac
}

# Check if package is installed
is_installed() {
    local pkg="$1"
    local manager="${2:-brew}"

    case "$manager" in
        brew)
            brew list "$pkg" &>/dev/null
            ;;
        apt)
            dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"
            ;;
        dnf|yum)
            rpm -q "$pkg" &>/dev/null
            ;;
        pacman)
            pacman -Q "$pkg" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# Non-Idempotent Operation Markers
# =============================================================================
warn_non_idempotent() {
    local operation="$1"
    warn "NON-IDEMPOTENT: $operation"
    verbose "This operation cannot be safely re-run without side effects"
}

# =============================================================================
# Dry-Run Summary
# =============================================================================
show_dryrun_summary() {
    if [[ "$DRY_RUN" == true ]]; then
        # Count operations from temp file (includes subshells)
        local count=0
        if [[ -f "$DRYRUN_COUNT_FILE" ]]; then
            count=$(wc -l < "$DRYRUN_COUNT_FILE" | tr -d ' ')
            rm -f "$DRYRUN_COUNT_FILE"
        fi
        # Also add local array count (for operations in main process)
        count=$((count + ${#DRYRUN_CHANGES[@]}))

        echo ""
        echo "═══════════════════════════════════════════════════════════"
        printf "  ${BLUE}DRY-RUN COMPLETE${NC} - No changes were made\n"
        echo "═══════════════════════════════════════════════════════════"
        echo ""
        printf "  %d operation(s) would be performed.\n" "$count"
        echo ""
        printf "  Run without ${YELLOW}--dry-run${NC} to apply changes.\n"
        echo ""
    fi
}

# Initialize dry-run counter file (call at start of main script)
init_dryrun() {
    if [[ "$DRY_RUN" == true ]]; then
        rm -f "$DRYRUN_COUNT_FILE"
        # Export the file path so subshells use the same file
        export DRYRUN_COUNT_FILE
    fi
}

# =============================================================================
# Link Tracking
# =============================================================================
LINKS_FILE="${DOTFILES_ROOT:-.}/.links"

# Record a symlink in the .links file
# Format: source -> target (same order as ln -s)
track_link() {
    local src="$1"
    local dst="$2"
    local entry="$src -> $dst"

    # Create file with header if it doesn't exist
    if [[ ! -f "$LINKS_FILE" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            printf "${GRAY}  [dry-run]${NC} Create %s\n" "$LINKS_FILE"
            _dryrun_count
        else
            echo "# Managed by dotfiles - do not edit manually" > "$LINKS_FILE"
            echo "# Format: source -> target" >> "$LINKS_FILE"
        fi
    fi

    # Check if already tracked
    if grep -qF "$entry" "$LINKS_FILE" 2>/dev/null; then
        verbose "Already tracked: $entry"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        printf "${GRAY}  [dry-run]${NC} Track: %s\n" "$entry"
        _dryrun_count
    else
        echo "$entry" >> "$LINKS_FILE"
        verbose "Tracked: $entry"
    fi
}

# Remove a symlink entry from .links file
untrack_link() {
    local src="$1"
    local dst="$2"
    local entry="$src -> $dst"

    if [[ ! -f "$LINKS_FILE" ]]; then
        return 0
    fi

    if ! grep -qF "$entry" "$LINKS_FILE" 2>/dev/null; then
        verbose "Not tracked: $entry"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        printf "${GRAY}  [dry-run]${NC} Untrack: %s\n" "$entry"
        _dryrun_count
    else
        # Remove the entry (portable sed)
        grep -vF "$entry" "$LINKS_FILE" > "$LINKS_FILE.tmp"
        mv "$LINKS_FILE.tmp" "$LINKS_FILE"
        verbose "Untracked: $entry"
    fi
}

# Get all tracked links as "source -> target" lines
get_tracked_links() {
    if [[ -f "$LINKS_FILE" ]]; then
        grep -v "^#" "$LINKS_FILE" | grep " -> " || true
    fi
}

# Find all symlinks in $HOME pointing to dotfiles repo
find_repo_symlinks() {
    local repo_path="${DOTFILES_ROOT:-$HOME/.dotfiles}"

    # Search common locations for symlinks pointing to our repo
    {
        # Hidden files in $HOME
        for f in "$HOME"/.*; do
            [[ -L "$f" ]] && [[ "$(readlink "$f")" == "$repo_path"* ]] && echo "$f"
        done
        # ~/.config contents
        if [[ -d "$HOME/.config" ]]; then
            for f in "$HOME/.config"/*; do
                [[ -L "$f" ]] && [[ "$(readlink "$f")" == "$repo_path"* ]] && echo "$f"
            done
        fi
        # ~/.local/bin contents
        if [[ -d "$HOME/.local/bin" ]]; then
            for f in "$HOME/.local/bin"/*; do
                [[ -L "$f" ]] && [[ "$(readlink "$f")" == "$repo_path"* ]] && echo "$f"
            done
        fi
    } 2>/dev/null | sort -u
}
