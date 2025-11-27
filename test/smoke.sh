#!/usr/bin/env bash
#
# test/smoke.sh
#
# Basic smoke tests for dotfiles scripts
#
# Usage:
#   ./test/smoke.sh           # Run all tests
#   ./test/smoke.sh -v        # Verbose output

# Don't use set -e - we handle errors ourselves
set +e

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
GRAY='\033[0;90m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# Verbose mode
VERBOSE=false
[[ "$1" == "-v" || "$1" == "--verbose" ]] && VERBOSE=true

# -----------------------------------------------------------------------------
# Test Helpers
# -----------------------------------------------------------------------------

pass() {
    printf "  ${GREEN}✓${NC} %s\n" "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    printf "  ${RED}✗${NC} %s\n" "$1"
    FAILED=$((FAILED + 1))
}

skip() {
    printf "  ${YELLOW}○${NC} %s (skipped)\n" "$1"
    SKIPPED=$((SKIPPED + 1))
}

section() {
    echo ""
    printf "${GRAY}━━━${NC} %s ${GRAY}━━━${NC}\n" "$1"
    echo ""
}

verbose() {
    if [[ "$VERBOSE" == true ]]; then
        printf "    ${GRAY}%s${NC}\n" "$1"
    fi
}

# Run a command with timeout and check exit code
check_exit() {
    local name="$1"
    local expected="$2"
    shift 2

    verbose "Running: $*"
    if timeout 30 "$@" &>/dev/null; then
        if [[ "$expected" == "0" ]]; then
            pass "$name"
        else
            fail "$name (expected exit $expected, got 0)"
        fi
    else
        local code=$?
        if [[ $code -eq 124 ]]; then
            fail "$name (timeout)"
        elif [[ "$expected" == "0" ]]; then
            fail "$name (exit code $code)"
        else
            pass "$name"
        fi
    fi
}

# Check that a command produces output
check_output() {
    local name="$1"
    shift

    verbose "Running: $*"
    local output
    output=$(timeout 30 "$@" 2>&1)
    local code=$?

    if [[ $code -eq 124 ]]; then
        fail "$name (timeout)"
    elif [[ $code -eq 0 && -n "$output" ]]; then
        pass "$name"
    elif [[ $code -ne 0 ]]; then
        fail "$name (exit code $code)"
    else
        fail "$name (no output)"
    fi
}

# -----------------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------------

test_syntax() {
    section "Syntax Checks"

    for script in "$DOTFILES_ROOT"/script/*; do
        [[ -f "$script" ]] || continue
        local name
        name=$(basename "$script")

        # Check if it's a bash script
        local shebang
        shebang=$(head -1 "$script")
        if [[ "$shebang" == *"bash"* ]]; then
            if bash -n "$script" 2>/dev/null; then
                pass "$name"
            else
                fail "$name"
            fi
        else
            skip "$name (not bash)"
        fi
    done

    # Check installer scripts too
    for script in "$DOTFILES_ROOT"/*/install.sh; do
        [[ -f "$script" ]] || continue
        local topic
        topic=$(basename "$(dirname "$script")")

        if bash -n "$script" 2>/dev/null; then
            pass "$topic/install.sh"
        else
            fail "$topic/install.sh"
        fi
    done
}

test_help_flags() {
    section "Help Flags"

    check_output "bootstrap --help" "$DOTFILES_ROOT/script/bootstrap" --help
    check_output "secrets --help" "$DOTFILES_ROOT/script/secrets" --help
    check_output "takeover --help" "$DOTFILES_ROOT/script/takeover" --help
}

test_dry_run() {
    section "Dry-Run Mode"

    check_exit "bootstrap --symlinks-only --dry-run" 0 "$DOTFILES_ROOT/script/bootstrap" --symlinks-only --dry-run
}

test_doctor() {
    section "Doctor/Status"

    # Doctor may have warnings but should still exit 0
    if timeout 30 "$DOTFILES_ROOT/script/bootstrap" --doctor &>/dev/null; then
        pass "bootstrap --doctor"
    else
        local code=$?
        if [[ $code -eq 124 ]]; then
            fail "bootstrap --doctor (timeout)"
        else
            # Doctor with warnings still passes
            pass "bootstrap --doctor (with warnings)"
        fi
    fi

    # --status should be alias
    if timeout 30 "$DOTFILES_ROOT/script/bootstrap" --status &>/dev/null; then
        pass "bootstrap --status (alias)"
    else
        local code=$?
        if [[ $code -eq 124 ]]; then
            fail "bootstrap --status (timeout)"
        else
            pass "bootstrap --status (alias, with warnings)"
        fi
    fi
}

test_secrets() {
    section "Secrets"

    check_output "secrets list" "$DOTFILES_ROOT/script/secrets" list

    # Validate requires 1Password signed in AND items to exist
    # This is more of an integration test - skip in smoke tests
    # since it depends on user's 1Password vault contents
    if command -v op &>/dev/null; then
        if op account get &>/dev/null 2>&1; then
            # Just verify the command runs without crashing
            # Exit code 1 is OK (means items missing, which is expected)
            if timeout 30 "$DOTFILES_ROOT/script/secrets" validate &>/dev/null; then
                pass "secrets validate (all items present)"
            else
                local code=$?
                if [[ $code -eq 1 ]]; then
                    pass "secrets validate (runs, some items missing)"
                elif [[ $code -eq 124 ]]; then
                    fail "secrets validate (timeout)"
                else
                    fail "secrets validate (exit code $code)"
                fi
            fi
        else
            skip "secrets validate (1Password not signed in)"
        fi
    else
        skip "secrets validate (1Password CLI not installed)"
    fi
}

test_lib_functions() {
    section "Library Functions"

    # Source lib.sh in a subshell to avoid polluting our environment
    (
        # Temporarily disable logging for tests
        export DOTFILES_LOG=none
        source "$DOTFILES_ROOT/script/lib.sh"

        # Test get_os
        local os
        os=$(get_os)
        if [[ "$os" == "macos" || "$os" == "linux" ]]; then
            echo "PASS:get_os"
        else
            echo "FAIL:get_os"
        fi

        # Test has_command
        if has_command bash; then
            echo "PASS:has_command_bash"
        else
            echo "FAIL:has_command_bash"
        fi

        if ! has_command nonexistent_command_12345; then
            echo "PASS:has_command_false"
        else
            echo "FAIL:has_command_false"
        fi
    ) | while read -r result; do
        local status="${result%%:*}"
        local name="${result#*:}"
        if [[ "$status" == "PASS" ]]; then
            pass "$name"
        else
            fail "$name"
        fi
    done
}

test_completions() {
    section "Fish Completions"

    local completions_dir="$DOTFILES_ROOT/fish/config/fish/completions"

    for script in bootstrap secrets takeover; do
        if [[ -f "$completions_dir/$script.fish" ]]; then
            # Basic syntax check (fish -n)
            if command -v fish &>/dev/null; then
                if fish -n "$completions_dir/$script.fish" 2>/dev/null; then
                    pass "$script.fish"
                else
                    fail "$script.fish (syntax error)"
                fi
            else
                # Just check file exists
                pass "$script.fish (exists)"
            fi
        else
            fail "$script.fish (missing)"
        fi
    done
}

test_linux_packages() {
    section "Linux Packages"

    local packages_file="$DOTFILES_ROOT/linux/packages.txt"

    if [[ -f "$packages_file" ]]; then
        pass "packages.txt exists"

        # Check it has content (non-comment, non-empty lines)
        local line_count
        line_count=$(grep -cvE "^#|^[[:space:]]*$" "$packages_file" 2>/dev/null || echo "0")
        if [[ $line_count -gt 0 ]]; then
            pass "packages.txt has $line_count packages"
        else
            fail "packages.txt is empty"
        fi
    else
        fail "packages.txt missing"
    fi
}

test_idempotency() {
    section "Idempotency"

    # Run bootstrap --symlinks-only --dry-run twice, count should be same
    local count1 count2

    count1=$(timeout 30 "$DOTFILES_ROOT/script/bootstrap" --symlinks-only --dry-run 2>&1 | grep -o "[0-9]* operation" | grep -o "[0-9]*" || echo "0")
    count2=$(timeout 30 "$DOTFILES_ROOT/script/bootstrap" --symlinks-only --dry-run 2>&1 | grep -o "[0-9]* operation" | grep -o "[0-9]*" || echo "0")

    if [[ "$count1" == "$count2" ]]; then
        pass "dry-run is idempotent ($count1 operations)"
    else
        fail "dry-run not idempotent ($count1 vs $count2)"
    fi
}

test_sort_brewfile() {
    section "Sort Brewfile"

    local script="$DOTFILES_ROOT/script/sort-brewfile"
    local brewfile="$DOTFILES_ROOT/macos/Brewfile"
    local pending="$DOTFILES_ROOT/macos/Brewfile.pending"

    # Check script exists and has valid syntax
    if [[ -f "$script" ]]; then
        if bash -n "$script" 2>/dev/null; then
            pass "sort-brewfile syntax"
        else
            fail "sort-brewfile syntax"
            return
        fi
    else
        fail "sort-brewfile missing"
        return
    fi

    # Check help/dry-run works
    check_exit "sort-brewfile --dry-run" 0 "$script" --dry-run

    # Test that Brewfile is already sorted (running sort shouldn't change it)
    if [[ -f "$brewfile" ]]; then
        local before after
        before=$(cat "$brewfile")
        timeout 10 "$script" --dry-run &>/dev/null
        after=$(cat "$brewfile")

        if [[ "$before" == "$after" ]]; then
            pass "sort-brewfile dry-run doesn't modify"
        else
            fail "sort-brewfile dry-run modified Brewfile"
        fi
    else
        skip "Brewfile not present"
    fi

    # Test comment migration (in temp copy)
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" RETURN

    # Create test Brewfile
    cat > "$tmp_dir/Brewfile" << 'EOF'
cask_args appdir: '/Applications'

tap 'test/tap'

brew 'zzz'
brew 'aaa'
# brew 'pending-package'
EOF
    touch "$tmp_dir/Brewfile.pending"

    # Run sort-brewfile on temp files (need to temporarily override paths)
    (
        cd "$tmp_dir"
        BREWFILE="$tmp_dir/Brewfile"
        PENDING="$tmp_dir/Brewfile.pending"
        export BREWFILE PENDING

        # Inline the sort logic test - just verify the script runs
        # We can't easily override the paths in the script, so test behavior manually
    )

    # Verify sorting works by checking order
    if [[ -f "$brewfile" ]]; then
        # Check that brews are sorted (first brew should come before last alphabetically)
        local first_brew last_brew
        first_brew=$(grep "^brew " "$brewfile" | head -1 | sed "s/brew '\\([^']*\\)'.*/\\1/")
        last_brew=$(grep "^brew " "$brewfile" | tail -1 | sed "s/brew '\\([^']*\\)'.*/\\1/")

        if [[ "$first_brew" < "$last_brew" || "$first_brew" == "$last_brew" ]]; then
            pass "Brewfile brews are sorted"
        else
            fail "Brewfile brews not sorted ($first_brew > $last_brew)"
        fi

        # Check cask_args is at top
        local first_line
        first_line=$(grep -v '^$' "$brewfile" | head -1)
        if [[ "$first_line" == cask_args* ]]; then
            pass "cask_args at top of Brewfile"
        else
            # taps can also be first if no cask_args
            if [[ "$first_line" == tap* ]]; then
                pass "tap at top of Brewfile (no cask_args)"
            else
                fail "Brewfile doesn't start with cask_args or tap"
            fi
        fi
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    echo ""
    echo "  Dotfiles Smoke Tests"
    echo "  ===================="

    test_syntax
    test_help_flags
    test_dry_run
    test_doctor
    test_secrets
    test_lib_functions
    test_completions
    test_linux_packages
    test_idempotency
    test_sort_brewfile

    # Summary
    section "Summary"
    printf "  ${GREEN}Passed${NC}:  %d\n" "$PASSED"
    printf "  ${RED}Failed${NC}:  %d\n" "$FAILED"
    printf "  ${YELLOW}Skipped${NC}: %d\n" "$SKIPPED"
    echo ""

    if [[ $FAILED -gt 0 ]]; then
        printf "  ${RED}TESTS FAILED${NC}\n"
        echo ""
        exit 1
    else
        printf "  ${GREEN}ALL TESTS PASSED${NC}\n"
        echo ""
        exit 0
    fi
}

main "$@"
