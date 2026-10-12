#!/bin/sh
# Idempotent bootstrap: system packages -> chezmoi -> dotfiles.
#
# Safe to run any number of times; a second run should change nothing.
# POSIX sh on purpose: a fresh machine has no fish yet.
#
#   ./bootstrap.sh [--skip-packages] [--dry-run]
#
# From a checkout this does everything. Piped (no checkout, so no package
# lists) it can only apply dotfiles, e.g. on a box where you have no root:
#   curl -fsSL <raw url>/bootstrap.sh | DOTFILES_REPO=<user>/dotfiles sh -s -- --skip-packages
#
# Environment:
#   DOTFILES_REPO     "<github-user>/<repo>" to clone when not run from a checkout
#   CHEZMOI_VERSION   pin a chezmoi release tag, e.g. v2.73.0 (default: latest)
#
# Deliberately NOT done here: GPG key import and pass setup. Secrets are a
# manual step; see README.md.
set -eu

SKIP_PACKAGES=0
DRY_RUN=0

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Execute, or just print under --dry-run.
run() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '    [dry-run] %s\n' "$*"
    else
        "$@"
    fi
}

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        run "$@"
    elif command -v sudo >/dev/null 2>&1; then
        run sudo "$@"
    else
        die "need root to install packages: run as root, install sudo, or pass --skip-packages"
    fi
}

for arg in "$@"; do
    case $arg in
        --skip-packages) SKIP_PACKAGES=1 ;;
        --dry-run) DRY_RUN=1 ;;
        -h | --help) sed -n '2,/^set -eu/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument: $arg" ;;
    esac
done

# When run from a file, locate the checkout; when piped (`| sh`), $0 is just "sh".
SCRIPT_DIR=
if [ -f "$0" ]; then
    SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
fi

# --- packages ---------------------------------------------------------------

package_manager() {
    if [ "$(uname -s)" = Darwin ]; then
        echo brew
    elif command -v apt-get >/dev/null 2>&1; then
        echo apt
    elif command -v dnf >/dev/null 2>&1; then
        echo dnf
    else
        echo none
    fi
}

is_installed() { # $1 = manager, $2 = package
    case $1 in
        apt) [ "$(dpkg-query -W -f='${db:Status-Status}' "$2" 2>/dev/null)" = installed ] ;;
        dnf) rpm -q "$2" >/dev/null 2>&1 ;;
        brew) brew list --formula "$2" >/dev/null 2>&1 ;;
    esac
}

install_packages() {
    pm=$(package_manager)
    [ "$pm" != none ] || die "no supported package manager (apt-get, dnf, brew) found"
    if [ -z "$SCRIPT_DIR" ] || [ ! -f "$SCRIPT_DIR/packages/$pm.txt" ]; then
        die "packages/$pm.txt not found; run bootstrap.sh from a checkout, or use --skip-packages"
    fi
    if [ "$pm" = brew ] && ! command -v brew >/dev/null 2>&1; then
        die "Homebrew is not installed: https://brew.sh"
    fi

    missing=$(
        while IFS= read -r pkg; do
            case $pkg in '' | '#'*) continue ;; esac
            is_installed "$pm" "$pkg" || printf '%s\n' "$pkg"
        done <"$SCRIPT_DIR/packages/$pm.txt"
    )

    if [ -z "$missing" ]; then
        log "packages: all present ($pm), nothing to install"
        return
    fi

    # shellcheck disable=SC2086 # package names never contain whitespace
    set -- $missing
    log "packages: installing $* ($pm)"
    case $pm in
        apt)
            as_root apt-get update -qq
            as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"
            ;;
        dnf) as_root dnf install -y -q "$@" ;;
        brew) run brew install "$@" ;; # brew refuses to run as root
    esac
}

if [ "$SKIP_PACKAGES" = 1 ]; then
    log "packages: skipped (--skip-packages)"
else
    install_packages
fi

command -v curl >/dev/null 2>&1 || die "curl is required to fetch chezmoi"

# --- chezmoi ----------------------------------------------------------------

BIN_DIR=$HOME/.local/bin
if command -v chezmoi >/dev/null 2>&1; then
    CHEZMOI=$(command -v chezmoi)
elif [ -x "$BIN_DIR/chezmoi" ]; then
    CHEZMOI=$BIN_DIR/chezmoi
else
    log "chezmoi: installing to $BIN_DIR"
    if [ "$DRY_RUN" = 1 ]; then
        printf '    [dry-run] curl -fsLS https://get.chezmoi.io | sh -s -- -b %s\n' "$BIN_DIR"
        CHEZMOI=$BIN_DIR/chezmoi
    else
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        mkdir -p "$BIN_DIR"
        # Download first so a failed fetch aborts instead of piping nothing to sh.
        curl -fsLS https://get.chezmoi.io -o "$tmp/install.sh"
        if [ -n "${CHEZMOI_VERSION:-}" ]; then
            sh "$tmp/install.sh" -b "$BIN_DIR" -t "$CHEZMOI_VERSION"
        else
            sh "$tmp/install.sh" -b "$BIN_DIR"
        fi
        CHEZMOI=$BIN_DIR/chezmoi
    fi
fi
log "chezmoi: $CHEZMOI"

# --- dotfiles ---------------------------------------------------------------

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/.chezmoiroot" ]; then
    log "dotfiles: applying from checkout $SCRIPT_DIR"
    run "$CHEZMOI" init --apply --source "$SCRIPT_DIR"
else
    [ -n "${DOTFILES_REPO:-}" ] ||
        die "not in a checkout: set DOTFILES_REPO=<github-user>/dotfiles"
    log "dotfiles: applying from github.com/$DOTFILES_REPO"
    run "$CHEZMOI" init --apply "$DOTFILES_REPO"
fi

log "done. Manual step left: import your GPG key and set up pass (see README, Secrets)."
