#!/usr/bin/env bash
#
# brew-audit.lib.sh
#
# Staging helpers for brew-audit. Buffers user choices into temp files
# and flushes them atomically at the end of a run. Extracted from the
# brew-audit script itself so tests can drive these functions directly
# without going through the interactive selection loop (which reads from
# /dev/tty and is hard to fake in CI).
#
# Caller contract — the following must be set before calling any function:
#
#   BREWFILE         path to the real Brewfile being appended to
#   PENDING          path to the real Brewfile.pending being appended to
#   BREWFILE_STAGED  temp file accumulating additions
#   PENDING_STAGED   temp file accumulating skips
#   DRY_RUN          "true" to print intent without writing
#   GRAY, NC         ANSI color escapes (or empty strings)
#   ADDED_COUNT      counter (mutated)
#   SKIPPED_COUNT    counter (mutated)
#
# Requires lib.sh to be sourced first for `fail`.
#
# Single-writer assumption: the lazy header / separator logic in
# add_to_pending checks $PENDING with `[[ -s ... ]]` at first-skip time.
# Two concurrent brew-audit processes would each see whatever $PENDING
# looked like before either appended, so their batches could end up
# concatenated without a separator. brew-audit doesn't acquire a lock,
# so concurrent runs are user-error and out of scope.

# Stage an addition to Brewfile.
add_to_brewfile() {
    : "${BREWFILE_STAGED:?required by brew-audit.lib.sh}"
    # Defensive init: bash treats unset numeric as 0 in arithmetic, but
    # we'd rather a caller-forgot-to-init regression surface as "0 added"
    # than as state bleeding from some other context.
    : "${ADDED_COUNT:=0}"
    local entry="$1"  # e.g. "brew 'foo'"

    if [[ "$DRY_RUN" == true ]]; then
        printf "${GRAY}  [dry-run]${NC} Would add: %s\n" "$entry"
    else
        echo "$entry" >> "$BREWFILE_STAGED" \
            || fail "Could not stage addition to $BREWFILE_STAGED"
    fi
    ADDED_COUNT=$((ADDED_COUNT + 1))
}

# Stage a skip into Brewfile.pending.
#
# Writes a single dated batch header on the first call of a run, then
# only the entry on subsequent calls — so the resulting pending file
# groups all skips under one timestamped header instead of repeating
# the header per package. A blank-line separator is included in the
# staged content when $PENDING already has prior content, keeping the
# eventual commit_appends call atomic.
add_to_pending() {
    : "${PENDING:?required by brew-audit.lib.sh}"
    : "${PENDING_STAGED:?required by brew-audit.lib.sh}"
    : "${SKIPPED_COUNT:=0}"
    local entry="$1"  # e.g. "brew 'foo'"

    if [[ "$DRY_RUN" == true ]]; then
        printf "${GRAY}  [dry-run]${NC} Would skip: # %s\n" "$entry"
    else
        if [[ ! -s "$PENDING_STAGED" ]]; then
            local today
            today=$(date +%Y-%m-%d) || fail "date command failed"
            [[ -n "$today" ]] || fail "date produced empty output"

            if [[ -s "$PENDING" ]]; then
                echo "" >> "$PENDING_STAGED" \
                    || fail "Could not stage separator to $PENDING_STAGED"
            fi
            printf '# Skipped by brew-audit on %s\n' "$today" >> "$PENDING_STAGED" \
                || fail "Could not stage header to $PENDING_STAGED"
        fi
        printf '# %s\n' "$entry" >> "$PENDING_STAGED" \
            || fail "Could not stage entry to $PENDING_STAGED"
    fi
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
}

# Flush staged additions to the real Brewfile / Brewfile.pending.
# Called once after selection completes, so a partial run leaves the
# tracked files untouched. On write failure (disk full, permission, RO
# filesystem), the staged content is copied out to a recoverable path
# next to the target before `fail` aborts — without this, the EXIT trap
# would drop the staged dir and the user would have no way to recover
# their selections.
commit_appends() {
    : "${BREWFILE:?required by brew-audit.lib.sh}"
    : "${PENDING:?required by brew-audit.lib.sh}"
    : "${BREWFILE_STAGED:?required by brew-audit.lib.sh}"
    : "${PENDING_STAGED:?required by brew-audit.lib.sh}"
    [[ "$DRY_RUN" == true ]] && return 0
    local timestamp recovery cp_err
    timestamp=$(date +%Y%m%d-%H%M%S) || fail "date command failed in commit_appends"
    [[ -n "$timestamp" ]] || fail "date produced empty timestamp"

    if [[ -s "$BREWFILE_STAGED" ]]; then
        if ! cat "$BREWFILE_STAGED" >> "$BREWFILE"; then
            recovery="${BREWFILE}.unsaved.${timestamp}"
            # Capture cp's stderr so the failure message names the actual
            # cause (e.g. "No space left on device") instead of just saying
            # "also failed".
            if cp_err=$(cp "$BREWFILE_STAGED" "$recovery" 2>&1); then
                fail "Failed to append staged additions to $BREWFILE. Recovery copy: $recovery"
            else
                fail "Failed to append staged additions to $BREWFILE (recovery copy also failed: $cp_err)"
            fi
        fi
    fi
    if [[ -s "$PENDING_STAGED" ]]; then
        if ! cat "$PENDING_STAGED" >> "$PENDING"; then
            recovery="${PENDING}.unsaved.${timestamp}"
            if cp_err=$(cp "$PENDING_STAGED" "$recovery" 2>&1); then
                fail "Failed to append staged skips to $PENDING. Recovery copy: $recovery"
            else
                fail "Failed to append staged skips to $PENDING (recovery copy also failed: $cp_err)"
            fi
        fi
    fi
}
