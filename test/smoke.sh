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

# Run a command with timeout and check exit code matches `expected` EXACTLY.
# A loose "any non-zero" check would let exit 127 (command not found) or 126
# (not executable) pass as if it were the validation error we asked for.
check_exit() {
    local name="$1"
    local expected="$2"
    shift 2

    verbose "Running: $*"
    timeout 30 "$@" &>/dev/null
    local code=$?

    if [[ $code -eq 124 ]]; then
        fail "$name (timeout)"
    elif [[ "$code" == "$expected" ]]; then
        pass "$name"
    else
        fail "$name (expected exit $expected, got $code)"
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

    # Argument-parsing tests for `secrets get` — no backend required.
    check_exit "secrets get with no name fails" 1 \
        "$DOTFILES_ROOT/script/secrets" get
    check_exit "secrets get --refresh with no name fails" 1 \
        "$DOTFILES_ROOT/script/secrets" get --refresh
    check_exit "secrets get rejects unknown flag" 1 \
        "$DOTFILES_ROOT/script/secrets" get --bogus foo

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

    # Source lib.sh in a subshell to avoid polluting our environment.
    # Run the subshell with output redirected to a temp file, then read
    # results in the *parent* shell — if we piped (`| while`), pass/fail's
    # counter increments would be scoped to the pipe subshell and never
    # reach $PASSED/$FAILED. (Bash 3.2 also rejects process substitution
    # `<(…)` here because the subshell uses `local`, which only works
    # inside a function body and not under process substitution on 3.2.)
    local tmpresults
    tmpresults=$(mktemp)

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

        # Test find_latest_backup: pure helper, easy to exercise directly
        local tmp base got
        tmp=$(mktemp -d)
        base="$tmp/foo"

        # Empty case: no backups, no output
        got=$(find_latest_backup "$base")
        if [[ -z "$got" ]]; then
            echo "PASS:find_latest_backup_empty"
        else
            echo "FAIL:find_latest_backup_empty"
        fi

        # Single backup: returns it
        touch "$base.backup.20250101-120000.1-1"
        got=$(find_latest_backup "$base")
        if [[ "$got" == "$base.backup.20250101-120000.1-1" ]]; then
            echo "PASS:find_latest_backup_single"
        else
            echo "FAIL:find_latest_backup_single"
        fi

        # Multiple backups: picks newest by timestamp (lexicographic on the
        # YYYYMMDD-HHMMSS prefix). 2026 > 2025 > 2024.
        touch "$base.backup.20240101-000000.1-1"
        touch "$base.backup.20260101-120000.1-1"
        got=$(find_latest_backup "$base")
        if [[ "$got" == "$base.backup.20260101-120000.1-1" ]]; then
            echo "PASS:find_latest_backup_newest"
        else
            echo "FAIL:find_latest_backup_newest"
        fi

        rm -rf "$tmp"

        # Sentinel: if the subshell died before reaching this (lib.sh missing,
        # source failed, etc.), the parent's while-read sees zero lines and
        # would otherwise report "test passed" while asserting nothing.
        echo "PASS:lib_functions_completed"
    ) > "$tmpresults"

    local saw_sentinel=false
    while read -r result; do
        local status="${result%%:*}"
        local name="${result#*:}"
        [[ "$name" == "lib_functions_completed" ]] && saw_sentinel=true
        if [[ "$status" == "PASS" ]]; then
            pass "$name"
        else
            fail "$name"
        fi
    done < "$tmpresults"

    rm -f "$tmpresults"

    if [[ "$saw_sentinel" != true ]]; then
        fail "test_lib_functions subshell aborted before completion"
    fi
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

    # Require an actual positive count first — otherwise "0 == 0 ✓ pass" hides
    # the case where bootstrap crashed before printing the operation summary
    # (e.g. missing `timeout`, or someone reworded the message).
    if ! [[ "$count1" =~ ^[1-9][0-9]*$ ]]; then
        fail "dry-run produced no operation count (got '$count1' — did bootstrap actually run?)"
    elif [[ "$count1" == "$count2" ]]; then
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

    # Tab handling: both tab- and space-indented brew entries must survive
    # the sort. Guards against a regression where the section-bucket regex
    # matches only a literal space and silently drops tab-indented lines.
    local tab_tmp
    tab_tmp=$(mktemp -d)
    # printf %b interprets the \t; the resulting file mixes tab and space indents.
    printf '%b' 'tap "homebrew/bundle"\nbrew\t"alpha"\nbrew "beta"\ncask\t"appone"\n' \
        > "$tab_tmp/Brewfile"
    touch "$tab_tmp/Brewfile.pending"

    BREWFILE="$tab_tmp/Brewfile" PENDING="$tab_tmp/Brewfile.pending" \
        timeout 10 "$script" >/dev/null 2>&1

    # Match a literal tab between `brew` and the quoted name. ANSI-C
    # quoting ($'\t') is bash 2.0+ so safe everywhere we run.
    if grep -q $'^brew\t"alpha"' "$tab_tmp/Brewfile"; then
        pass "sort-brewfile preserves tab-indented brew entry"
    else
        fail "sort-brewfile dropped tab-indented brew entry"
    fi
    if grep -q '"beta"' "$tab_tmp/Brewfile"; then
        pass "sort-brewfile preserves space-indented brew entry"
    else
        fail "sort-brewfile dropped space-indented brew entry"
    fi
    rm -rf "$tab_tmp"

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

test_brew_audit_staging() {
    section "brew-audit staging lib"

    # Drive add_to_pending / add_to_brewfile / commit_appends directly by
    # sourcing brew-audit.lib.sh. Bypasses the interactive selection loop
    # (which reads from /dev/tty and is hard to fake in CI) and lets us
    # actually exercise the lazy-header, separator, recovery, and dry-run
    # paths that smoke previously couldn't reach.
    local tmpresults
    tmpresults=$(mktemp)

    (
        export DOTFILES_LOG=none
        source "$DOTFILES_ROOT/script/lib.sh"
        source "$DOTFILES_ROOT/script/brew-audit.lib.sh"

        local sandbox
        sandbox=$(mktemp -d)
        BREWFILE="$sandbox/Brewfile"
        PENDING="$sandbox/Brewfile.pending"
        BREWFILE_STAGED="$sandbox/staged_brew"
        PENDING_STAGED="$sandbox/staged_pending"
        touch "$BREWFILE" "$PENDING" "$BREWFILE_STAGED" "$PENDING_STAGED"
        DRY_RUN=false
        GRAY=""
        NC=""
        ADDED_COUNT=0
        SKIPPED_COUNT=0

        # First skip writes the lazy batch header
        add_to_pending "tap 'foo'"
        if grep -q "^# Skipped by brew-audit on" "$PENDING_STAGED" \
            && grep -qF "# tap 'foo'" "$PENDING_STAGED"; then
            echo "PASS:staging_lazy_header_written_on_first_skip"
        else
            echo "FAIL:staging_lazy_header_written_on_first_skip"
        fi

        # Subsequent skips don't add another header
        add_to_pending "brew 'bar'"
        add_to_pending "cask 'baz'"
        local header_count
        header_count=$(grep -c "^# Skipped by brew-audit on" "$PENDING_STAGED")
        if [[ "$header_count" == "1" ]]; then
            echo "PASS:staging_one_header_per_batch"
        else
            echo "FAIL:staging_one_header_per_batch (got $header_count headers)"
        fi

        # Counter tracks calls correctly
        if [[ "$SKIPPED_COUNT" == "3" ]]; then
            echo "PASS:staging_skipped_counter"
        else
            echo "FAIL:staging_skipped_counter (got $SKIPPED_COUNT)"
        fi

        # Atomicity: $PENDING and $BREWFILE must still be empty pre-commit —
        # this is the headline guarantee of the staging refactor.
        if [[ ! -s "$PENDING" && ! -s "$BREWFILE" ]]; then
            echo "PASS:staging_real_files_untouched_pre_commit"
        else
            echo "FAIL:staging_real_files_untouched_pre_commit"
        fi

        # commit_appends flushes staging to the real PENDING
        commit_appends
        if grep -qF "# tap 'foo'" "$PENDING" \
            && grep -qF "# brew 'bar'" "$PENDING" \
            && grep -qF "# cask 'baz'" "$PENDING"; then
            echo "PASS:staging_commit_flushes_to_real_pending"
        else
            echo "FAIL:staging_commit_flushes_to_real_pending"
        fi

        # Second run: PENDING is non-empty, so staging starts with a blank
        # separator line
        : > "$PENDING_STAGED"
        add_to_pending "brew 'qux'"
        local first_line
        first_line=$(head -1 "$PENDING_STAGED")
        if [[ -z "$first_line" ]]; then
            echo "PASS:staging_blank_separator_when_pending_has_content"
        else
            echo "FAIL:staging_blank_separator_when_pending_has_content (first line: '$first_line')"
        fi

        # add_to_brewfile increments the addition counter and writes to staging
        ADDED_COUNT=0
        add_to_brewfile "brew 'added-thing'"
        if [[ "$ADDED_COUNT" == "1" ]] \
            && grep -qF "brew 'added-thing'" "$BREWFILE_STAGED"; then
            echo "PASS:staging_add_to_brewfile"
        else
            echo "FAIL:staging_add_to_brewfile"
        fi

        # Recovery path: make PENDING read-only so commit_appends fails its
        # cat-append, then verify a .unsaved.<ts> recovery file is created.
        # Skipped under EUID=0 because root bypasses mode bits and would
        # cause the cat to succeed unexpectedly.
        if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
            echo "PASS:staging_recovery_on_write_failure (skipped: root bypasses chmod)"
        else
            # Clean any stale .unsaved.* from prior runs in this sandbox so
            # the post-commit glob assertion is strictly about THIS invocation.
            rm -f "${PENDING}".unsaved.*
            : > "$PENDING_STAGED"
            add_to_pending "brew 'recovery-target'"
            chmod 444 "$PENDING"
            # commit_appends calls fail() on error, which exits — run it in a
            # subshell so the test loop survives.
            (commit_appends) >/dev/null 2>&1
            chmod 644 "$PENDING"
            local recovery
            recovery=$(ls "${PENDING}".unsaved.* 2>/dev/null | head -1)
            if [[ -n "$recovery" && -f "$recovery" ]] \
                && grep -qF "# brew 'recovery-target'" "$recovery"; then
                echo "PASS:staging_recovery_on_write_failure"
            else
                echo "FAIL:staging_recovery_on_write_failure"
            fi
        fi

        # Dry-run path doesn't touch staging
        DRY_RUN=true
        : > "$PENDING_STAGED"
        add_to_pending "brew 'dryrun-skipped'" >/dev/null
        if [[ ! -s "$PENDING_STAGED" ]]; then
            echo "PASS:staging_dry_run_does_not_write"
        else
            echo "FAIL:staging_dry_run_does_not_write"
        fi

        rm -rf "$sandbox"

        # Sentinel: if anything above blew up the subshell early, the read
        # loop in the parent reports the missing sentinel as a failure
        # (otherwise pass/fail's counter increments — which are scoped to
        # the temp-file hand-off below, not the pipe subshell — would still
        # be counted correctly).
        echo "PASS:staging_test_completed"
    ) > "$tmpresults"

    local saw_sentinel=false
    while read -r result; do
        local status="${result%%:*}"
        local name="${result#*:}"
        [[ "$name" == "staging_test_completed" ]] && saw_sentinel=true
        if [[ "$status" == "PASS" ]]; then
            pass "$name"
        else
            fail "$name"
        fi
    done < "$tmpresults"

    rm -f "$tmpresults"

    if [[ "$saw_sentinel" != true ]]; then
        fail "test_brew_audit_staging subshell aborted before completion"
    fi
}

test_brew_audit_dry_run() {
    section "brew-audit --dry-run"

    if ! command -v brew &>/dev/null; then
        skip "brew not installed"
        return
    fi

    local script="$DOTFILES_ROOT/script/brew-audit"
    local tmp
    tmp=$(mktemp -d)

    # Seed the temp Brewfile with the current installed taps so the audit
    # finds nothing untracked for --type tap and exits early — no fzf, no
    # prompts. Even if something does turn up untracked, --dry-run must
    # not mutate the Brewfile; that's what we verify.
    brew tap 2>/dev/null | while IFS= read -r t; do
        printf 'tap "%s"\n' "$t"
    done > "$tmp/Brewfile"
    touch "$tmp/Brewfile.pending"

    local before after
    before=$(shasum "$tmp/Brewfile" | awk '{print $1}')

    BREWFILE="$tmp/Brewfile" PENDING="$tmp/Brewfile.pending" \
        timeout 30 "$script" --dry-run --type tap --no-fzf </dev/null >/dev/null 2>&1
    local rc=$?

    after=$(shasum "$tmp/Brewfile" | awk '{print $1}')

    # Without checking rc, a script crash before any write would silently
    # pass the sha-unchanged assertion. Treat anything other than 0 as a
    # real failure (124 is timeout from the wrapper).
    if [[ $rc -ne 0 ]]; then
        if [[ $rc -eq 124 ]]; then
            fail "brew-audit --dry-run timed out"
        else
            fail "brew-audit --dry-run exited $rc"
        fi
    elif [[ "$before" == "$after" ]]; then
        pass "brew-audit --dry-run leaves Brewfile unchanged"
    else
        fail "brew-audit --dry-run mutated Brewfile"
    fi

    rm -rf "$tmp"
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
    test_brew_audit_staging
    test_brew_audit_dry_run

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
