#!/bin/sh
# Runs as an ordinary user with sudo. Bootstraps twice and asserts that the
# second run is a no-op. Also usable directly with a throwaway HOME:
#   HOME=$(mktemp -d) BOOTSTRAP_ARGS=--skip-packages sh tests/assert.sh
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BOOTSTRAP_ARGS=${BOOTSTRAP_ARGS:-}
LOG=$(mktemp -d)
export PATH="$HOME/.local/bin:$PATH"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok:   %s\n' "$*"; }

# Content hash of every file under $HOME, minus chezmoi's own bookkeeping
# (its state DB is rewritten on each run and is not a dotfile).
snapshot() {
    find "$HOME" \
        \( -path "$HOME/.cache" -o -path "$HOME/.config/chezmoi/chezmoistate.boltdb" \) -prune \
        -o -type f -print0 | sort -z | xargs -0 sha256sum
}

# Installed package set, so "no packages changed" is checked rather than assumed.
packages() {
    if command -v dpkg-query >/dev/null 2>&1; then
        dpkg-query -W -f='${Package} ${Version}\n' | sort
    elif command -v rpm >/dev/null 2>&1; then
        rpm -qa | sort
    fi
}

# Log to a file, then show it. Piping into tee would hide a non-zero exit in dash.
# shellcheck disable=SC2086 # BOOTSTRAP_ARGS is a space-separated flag list
bootstrap() { # $1 = log file
    if ! sh "$ROOT/bootstrap.sh" $BOOTSTRAP_ARGS >"$1" 2>&1; then
        cat "$1"
        fail "bootstrap exited non-zero"
    fi
    cat "$1"
}

echo "--- run 1 ---"
bootstrap "$LOG/run1.log"
snapshot >"$LOG/files1"
packages >"$LOG/pkgs1"

echo "--- run 2 ---"
bootstrap "$LOG/run2.log"
snapshot >"$LOG/files2"
packages >"$LOG/pkgs2"

echo "--- assertions ---"

cmp -s "$LOG/files1" "$LOG/files2" || {
    diff "$LOG/files1" "$LOG/files2" || true
    fail "run 2 changed files under \$HOME"
}
pass "file tree identical after run 2"

cmp -s "$LOG/pkgs1" "$LOG/pkgs2" || fail "run 2 changed installed packages"
pass "installed packages identical after run 2"

if grep -Eq 'packages: installing|chezmoi: installing' "$LOG/run2.log"; then
    fail "run 2 tried to install something"
fi
pass "run 2 installed nothing"

# An empty diff proves nothing if chezmoi found no source, so check it manages
# the files we expect before trusting diff/verify.
managed=$(chezmoi managed)
for f in .bashrc .gitconfig .config/fish/config.fish; do
    printf '%s\n' "$managed" | grep -qx "$f" || fail "chezmoi does not manage $f"
done
pass "chezmoi manages .bashrc, .gitconfig, fish config"

[ -z "$(chezmoi diff)" ] || fail "chezmoi diff is not empty after apply"
chezmoi verify || fail "chezmoi verify failed"
pass "chezmoi diff empty, verify clean"

[ "$(grep -c '^# >>> dotfiles >>>$' "$HOME/.bashrc")" = 1 ] ||
    fail ".bashrc does not contain exactly one managed block"
pass ".bashrc has exactly one managed block"

grep -q 'users.noreply.github.com' "$HOME/.gitconfig" || fail ".gitconfig missing identity"
pass ".gitconfig rendered from template"

if command -v fish >/dev/null 2>&1; then
    fish --no-execute "$HOME/.config/fish/config.fish" || fail "fish config has syntax errors"
    pass "fish config parses"
fi

echo "ALL CHECKS PASSED"
