#!/bin/bash
# Make this Omarchy install look and behave like mehexi's PC.
#
#   ./install.sh                 everything
#   ./install.sh --skip-themes   don't clone the extra themes (~1.7 GB)
#   ./install.sh --skip-icons    don't install the MacTahoe icon theme
#   ./install.sh --yes           don't ask before changing anything
#
# Every file it replaces is backed up first to
# ~/.config/omarchy-dotfiles-backup/<timestamp>/.
#
# Re-running is safe: it backs up again, copies again, and skips work already done.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKIP_THEMES=0
SKIP_ICONS=0
ASSUME_YES=0
for a in "$@"; do
  case $a in
    --skip-themes) SKIP_THEMES=1 ;;
    --skip-icons) SKIP_ICONS=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 1 ;;
  esac
done

say() { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m!!\e[0m %s\n' "$*" >&2; }

command -v omarchy >/dev/null || { echo "This doesn't look like Omarchy (no 'omarchy' command)." >&2; exit 1; }
command -v git >/dev/null || { echo "git is required." >&2; exit 1; }
command -v rsync >/dev/null || { say "Installing rsync"; sudo pacman -S --needed --noconfirm rsync; }

# These dots only support ~/.config; a different XDG_CONFIG_HOME would split them.
if [[ -n ${XDG_CONFIG_HOME:-} && "$(realpath -m "$XDG_CONFIG_HOME")" != "$(realpath -m "$HOME/.config")" ]]; then
  echo "XDG_CONFIG_HOME is set to $XDG_CONFIG_HOME. These dots only support ~/.config." >&2
  exit 1
fi

if (( ! ASSUME_YES )); then
  cat <<EOF
This replaces, in your home folder:
  - the Omarchy shell plugins, bar layout and look  -> ~/.config/omarchy/
  - Hyprland look and keys                          -> ~/.config/hypr/
    (monitors.lua and autostart.lua are left alone)
  - fastfetch, foot, alacritty, kitty, ghostty, btop, tmux
  - helper scripts                                  -> ~/.local/share, ~/.local/bin
  - Theme Studio, Tricky Tiles and Softly from their own GitHub repos
  - one system package if missing: qt6-5compat (asks for your password)

Everything it replaces is backed up to ~/.config/omarchy-dotfiles-backup/<time>/.
EOF
  read -r -p "Continue? [y/N] " answer || answer=""
  [[ $answer == [yY]* ]] || { echo "Nothing changed."; exit 0; }
fi

# shellcheck source=/dev/null
source "$REPO/state.env"

# --- 1. System package -------------------------------------------------------
# The rail and the floating bar draw their edges with Qt5Compat.GraphicalEffects.
if ! pacman -Q qt6-5compat >/dev/null 2>&1; then
  say "Installing qt6-5compat"
  omarchy-pkg-add qt6-5compat || sudo pacman -S --needed --noconfirm qt6-5compat \
    || warn "could not install qt6-5compat; the bar will fall back to Omarchy's own"
fi

# --- 2. Config files ---------------------------------------------------------
BACKUP="$HOME/.config/omarchy-dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
say "Backing up files that will be replaced to $BACKUP"
(cd "$REPO/config" && find . -type f) | while read -r f; do
  f=${f#./}
  if [[ -e $HOME/.config/$f ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp -a "$HOME/.config/$f" "$BACKUP/$f"
  fi
done

say "Copying config into ~/.config"
rsync -a "$REPO/config/" "$HOME/.config/"
find "$HOME/.config/omarchy/bar/scripts" "$HOME/.config/omarchy/bin" "$HOME/.config/omarchy/hooks" \
  -type f ! -name '*.json' -exec chmod +x {} + 2>/dev/null || true

# keywatch plugin had the old username baked in
sed -i "s|/home/[^/]*/.config/omarchy/plugins|$HOME/.config/omarchy/plugins|g" \
  "$HOME/.config/omarchy/plugins/mehezi.keywatch/KeyWatch.qml" 2>/dev/null || true

# --- 3. Helper scripts outside ~/.config ------------------------------------
if [[ -d $REPO/local ]]; then
  say "Installing helper scripts into ~/.local"
  (cd "$REPO/local" && find . -type f) | while read -r f; do
    f=${f#./}
    if [[ -e $HOME/.local/$f ]]; then
      mkdir -p "$BACKUP/.local/$(dirname "$f")"
      cp -a "$HOME/.local/$f" "$BACKUP/.local/$f"
    fi
  done
  rsync -a "$REPO/local/" "$HOME/.local/"
  chmod +x "$HOME"/.local/bin/* 2>/dev/null || true
  find "$HOME/.local/share/omarchy-glass" "$HOME/.local/share/omarchy-recess" \
       "$HOME/.local/share/touchpad-control" "$HOME/.local/share/denon-agent-usage" \
       -name '*.py' -exec chmod +x {} + 2>/dev/null || true
fi

# --- 4. Plugins that live in their own repos --------------------------------
# Added from upstream, then any file we changed is laid back over the clone.
if [[ -f $REPO/externals.txt ]]; then
  say "Adding Theme Studio, Tricky Tiles and Softly"
  while read -r id url; do
    [[ -z ${id:-} || -z ${url:-} ]] && continue
    if [[ -f $HOME/.config/omarchy/plugins/$id/manifest.json ]]; then
      echo "  $id (already there)"
      omarchy plugin enable "$id" >/dev/null 2>&1 || true
    else
      echo "  $id"
      omarchy plugin add "$url" --enable --yes >/dev/null 2>&1 \
        || warn "could not add $url (later: omarchy plugin add $url --enable)"
    fi
  done < "$REPO/externals.txt"
fi

if [[ -d $REPO/patches ]]; then
  say "Applying our changes to those plugins"
  (cd "$REPO/patches" && find . -type f) | while read -r f; do
    f=${f#./}
    dest="$HOME/.config/omarchy/plugins/$f"
    if [[ -e $dest ]]; then
      mkdir -p "$BACKUP/plugins-upstream/$(dirname "$f")"
      cp -a "$dest" "$BACKUP/plugins-upstream/$f"
      cp -a "$REPO/patches/$f" "$dest"
      echo "  $f"
    else
      warn "skipped patch, plugin not installed: $f"
    fi
  done
  # Theme Studio caches Openverse-shaped search results; ours come from Wallhaven.
  rm -rf "$HOME/.cache/omarchy-theme-studio/wallpapers/search"
fi

# --- 5. Themes ---------------------------------------------------------------
if (( ! SKIP_THEMES )); then
  say "Installing themes"
  mkdir -p "$HOME/.config/omarchy/themes"
  while read -r name url; do
    [[ -z ${name:-} ]] && continue
    dir="$HOME/.config/omarchy/themes/$name"
    if [[ -d $dir ]]; then
      echo "  $name (already there)"
    else
      echo "  $name"
      git clone -q --depth 1 -- "$url" "$dir" || warn "could not clone $url"
    fi
  done < "$REPO/themes.txt"
fi

# --- 6. MacTahoe icons (with the brighter folder blue) ----------------------
if (( ! SKIP_ICONS )) && [[ -n ${ICON_THEME:-} ]]; then
  if [[ ! -d $HOME/.local/share/icons/MacTahoe-dark ]]; then
    say "Installing MacTahoe icon theme"
    tmp=$(mktemp -d)
    git clone -q --depth 1 https://github.com/vinceliuice/MacTahoe-icon-theme.git "$tmp/mactahoe"
    (cd "$tmp/mactahoe" && ./install.sh >/dev/null)
    rm -rf "$tmp"
  fi
  say "Recolouring MacTahoe folders to Tahoe sky blue"
  for v in MacTahoe MacTahoe-dark; do
    d="$HOME/.local/share/icons/$v/places/scalable"
    [[ -d $d ]] || continue
    find -L "$d" -name '*.svg' -type f -exec sed -i \
      -e 's/#88ccf2/#7cd0ff/Ig' -e 's/#7cc1ea/#5bbdfb/Ig' -e 's/#67b1de/#3aa7f5/Ig' \
      -e 's/#56a1d3/#2492ea/Ig' -e 's/#46a2d7/#1f8ae0/Ig' {} +
  done
  gtk-update-icon-cache -q "$HOME/.local/share/icons/MacTahoe-dark" 2>/dev/null || true
fi

# --- 7. Apply theme, background, font, icons -------------------------------
if [[ -n ${THEME:-} ]]; then
  say "Setting theme $THEME"
  omarchy theme set "$THEME" || warn "theme '$THEME' not available (skipped themes?)"
fi

if [[ -n ${BACKGROUND:-} ]]; then
  bg="$HOME/.local/state/omarchy/current/theme/backgrounds/$BACKGROUND"
  [[ -f $bg ]] && { say "Setting background"; omarchy theme bg set "$bg" || true; }
fi

if [[ -n ${FONT:-} ]] && [[ $(omarchy font current 2>/dev/null) != "$FONT" ]]; then
  say "Setting font $FONT"
  omarchy font set "$FONT" || warn "font '$FONT' not installed"
fi

if [[ -n ${ICON_THEME:-} ]] && (( ! SKIP_ICONS )); then
  gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME" || true
fi

# --- 8. Reload ---------------------------------------------------------------
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  say "Reloading Hyprland and the Omarchy shell"
  hyprctl reload >/dev/null || true
  errs=$(hyprctl configerrors 2>/dev/null || true)
  [[ -n $errs && $errs != *"no errors"* ]] && warn "Hyprland config errors: $errs"
  omarchy restart shell >/dev/null 2>&1 || warn "restart the shell with: omarchy restart shell"
else
  warn "Not inside Hyprland — log in and everything loads on its own."
fi

say "Done. Backup of replaced files: $BACKUP"
