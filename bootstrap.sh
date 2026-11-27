#!/bin/bash
# One-command install of mehexi's Omarchy setup, on any Omarchy 4 machine:
#
#   curl -fsSL https://mehexi.github.io/omarchy-dotfiles/install | bash
#
# or, straight from the repo:
#
#   curl -fsSL https://raw.githubusercontent.com/mehexi/omarchy-dotfiles/main/bootstrap.sh | bash
#
# Arguments are passed through to install.sh, so this works too:
#
#   curl -fsSL .../bootstrap.sh | bash -s -- --skip-themes
#
# It clones (or updates) the repo in ~/.local/share/omarchy-dotfiles and runs
# install.sh from there, so the checkout stays around for later re-runs.
set -euo pipefail

REPO_URL="${DOTFILES_REPO:-https://github.com/mehexi/omarchy-dotfiles}"
BRANCH="${DOTFILES_BRANCH:-main}"
DEST="${DOTFILES_DIR:-$HOME/.local/share/omarchy-dotfiles}"

say() { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
die() { printf '\e[1;31m!!\e[0m %s\n' "$*" >&2; exit 1; }

command -v omarchy >/dev/null || die "This doesn't look like Omarchy (no 'omarchy' command). See https://omarchy.org"
command -v git >/dev/null || die "git is required."

if [[ -d $DEST/.git ]]; then
  say "Updating $DEST"
  git -C "$DEST" remote set-url origin "$REPO_URL"
  git -C "$DEST" fetch --depth 1 origin "$BRANCH"
  git -C "$DEST" reset --hard "origin/$BRANCH"
else
  say "Cloning into $DEST"
  rm -rf "$DEST"
  mkdir -p "$(dirname "$DEST")"
  git clone --depth 1 --branch "$BRANCH" -- "$REPO_URL" "$DEST"
fi

chmod +x "$DEST/install.sh" "$DEST/sync.sh" 2>/dev/null || true

# Piped into bash, this script IS stdin, so install.sh's confirmation prompt
# would read the rest of the pipe instead of the person. Give it the terminal
# back when there is one; when there genuinely is no terminal (CI, a hook),
# answer for it rather than hanging on a prompt nobody can see.
if [[ -r /dev/tty ]]; then
  exec "$DEST/install.sh" "$@" </dev/tty
else
  say "No terminal attached — running unattended"
  exec "$DEST/install.sh" --yes "$@"
fi
