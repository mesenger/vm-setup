# dotfiles

Personal dotfiles, managed with [chezmoi](https://www.chezmoi.io/), plus a
bootstrap script that takes a fresh machine to a working setup and can be run
repeatedly without changing anything the second time.

## New machine

Needs `git` and `curl` (on a bare VM: `sudo apt-get install -y git curl`).

```sh
git clone https://github.com/<github-user>/dotfiles ~/dotfiles
~/dotfiles/bootstrap.sh
```

Git identity is set in `home/dot_gitconfig.tmpl`: a display name and your
GitHub noreply address (public by design, so it is safe in a public repo).
Nothing is prompted; edit that file to change it.

Options: `--dry-run` shows what would happen, `--skip-packages` applies only the
dotfiles (no root needed), `CHEZMOI_VERSION=v2.73.0` pins the chezmoi release.

## What it does

1. Detects `apt`, `dnf` or `brew` and installs whatever is **missing** from
   `packages/<manager>.txt` (checks first, so a satisfied run touches nothing,
   not even `apt-get update`).
2. Installs chezmoi to `~/.local/bin` if absent.
3. `chezmoi init --apply` from this checkout.

What it deliberately **does not** do:

- **Import GPG keys or initialise `pass`.** See [Secrets](#secrets).
- **`chsh` to fish.** bash stays the login shell; see [Shell](#shell).

## Layout

```
bootstrap.sh              POSIX sh (fish isn't installed yet on a fresh box)
packages/{apt,dnf,brew}.txt
home/                     chezmoi source root (set by .chezmoiroot)
  .chezmoi.toml.tmpl        points chezmoi at this checkout
  dot_gitconfig.tmpl        identity + defaults; osxkeychain helper on macOS
  dot_config/fish/config.fish.tmpl
  modify_dot_bashrc         owns one marked block in ~/.bashrc, nothing else
tests/                    idempotency check (see below)
.github/workflows/ci.yml  lint + gitleaks + idempotency on every push
```

## Shell

`~/.bashrc` is not replaced. A marker-delimited block is appended (and replaced,
never duplicated, on re-apply) that sets `GPG_TTY` and starts fish for
interactive shells. Because bash remains the login shell, a broken fish cannot
lock you out.

- Skip the handoff for one session: `DOTFILES_NO_FISH=1 bash`
- A `bash` started from inside fish is left alone.

## Idempotency

The claim is: run the bootstrap twice and the second run changes nothing. It is
checked, not assumed. `tests/idempotency.sh` starts a clean container, creates
an unprivileged user with sudo, runs the bootstrap twice, and asserts that:

- every file under `$HOME` has identical content after run 2 (chezmoi's own
  state DB excluded);
- the installed package set is identical;
- run 2 never reached an install step;
- `chezmoi managed` lists the expected files, and `chezmoi diff` is empty and
  `chezmoi verify` passes;
- `.bashrc` contains exactly one managed block.

Run it locally (rootless podman is fine) or with docker:

```sh
tests/idempotency.sh              # ubuntu:24.04
tests/idempotency.sh ubuntu:26.04
```

CI runs the same script on Ubuntu 24.04 and 26.04 for every push. To check just
the dotfiles half without a container engine:

```sh
HOME=$(mktemp -d) BOOTSTRAP_ARGS=--skip-packages sh tests/assert.sh
```

Coverage: CI exercises the `apt` path. The `dnf` and `brew` paths are
implemented but not yet covered by CI.

## Secrets

This repo is public, so it contains no tokens, no private hostnames, and no real
email. [gitleaks](https://github.com/gitleaks/gitleaks) runs as a pre-commit hook
and over full history in CI:

```sh
pipx install pre-commit && pre-commit install
```

Your GPG **private key never goes in any repo.** The bootstrap installs `gpg`
and `pass` and stops. Import is a deliberate manual step:

```sh
# on the machine that holds the key; move the file over a trusted channel
gpg --export-secret-keys --armor <key-id> > key.asc

# on the new machine
gpg --import key.asc && shred -u key.asc
gpg --edit-key <key-id> trust        # set trust to ultimate
```

The password store itself lives in a **separate private repo**: entry names are
metadata, even though the contents are encrypted. Clone the existing store, or
start a fresh one:

```sh
git clone <private-store-url> ~/.password-store   # existing store: no init needed
pass init <key-id>                                # brand-new store only
```
