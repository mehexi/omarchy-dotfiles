#!/bin/bash
# Copy this PC's Omarchy customization INTO the repo (run on the source PC,
# then commit + push). install.sh does the reverse on any other Omarchy box.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HOME/.config"
DST="$REPO/config"

# Paths (relative to ~/.config) that make up the customization.
PATHS=(
  omarchy/plugins
  omarchy/bar
  omarchy/bin
  omarchy/branding
  omarchy/extensions
  omarchy/hooks
  omarchy/shell.json
  omarchy/shell.toml
  hypr/hyprland.lua
  hypr/bindings.lua
  hypr/looknfeel.lua
  alacritty/alacritty.toml
  foot/foot.ini
  ghostty/config
  kitty/kitty.conf
  btop/btop.conf
  tmux/tmux.conf
)

rm -rf "$DST"
mkdir -p "$DST"
for p in "${PATHS[@]}"; do
  [[ -e $SRC/$p ]] || { echo "skip (missing): $p"; continue; }
  mkdir -p "$DST/$(dirname "$p")"
  rsync -a --exclude='*.bak' --exclude='*.bak.*' --exclude='*.bak2.*' \
    --exclude='*.sample' --exclude='*.pre-glass.*' --exclude='*.omarchy-upgrade-*' \
    "$SRC/$p" "$DST/$(dirname "$p")/"
done

# Installed git themes: "<dir-name> <clone-url>" per line.
: > "$REPO/themes.txt"
for t in "$SRC"/omarchy/themes/*/; do
  name=$(basename "$t")
  url=$(git -C "$t" remote get-url origin 2>/dev/null || true)
  if [[ -n $url ]]; then
    echo "$name $url" >> "$REPO/themes.txt"
  else
    echo "warning: theme '$name' is not a git clone, not synced" >&2
  fi
done

# Current look.
STATE="$HOME/.local/state/omarchy/current"
bg=$(readlink "$STATE/background" 2>/dev/null || true)
cat > "$REPO/state.env" <<EOF
THEME="$(cat "$STATE/theme.name" 2>/dev/null)"
BACKGROUND="$(basename "${bg:-}")"
FONT="$(omarchy font current 2>/dev/null || true)"
ICON_THEME="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")"
EOF

echo "Synced into $REPO. Review with: git -C '$REPO' status"
