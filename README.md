# omarchy-dotfiles

My Omarchy setup: macOS-Tahoe-style shell plugins (pill bar, control center,
Launchpad on SUPER+SPACE, lock screen, clock/weather/tray clones, phone panel),
bar scripts, menu extensions, hooks, Hyprland overrides (blur, animations,
bindings, layer rules), terminal configs, 22 extra themes, MacTahoe icons with
the brighter folder blue.

## Put it on another Omarchy machine

```bash
git clone https://github.com/mehexi/omarchy-dotfiles ~/omarchy-dotfiles
~/omarchy-dotfiles/install.sh
```

(Private repo: run `gh auth login` first, or use `gh repo clone mehexi/omarchy-dotfiles ~/omarchy-dotfiles`.)

Options: `--skip-themes` (saves ~1.7 GB of theme clones), `--skip-icons`.
Every file it replaces is backed up to `~/.config/omarchy-dotfiles-backup/<time>/`.

## Update the repo after changing things on this PC

```bash
~/Projects/omarchy-dotfiles/sync.sh
cd ~/Projects/omarchy-dotfiles && git add -A && git commit -m "Update" && git push
```

## Not included

- `hypr/monitors.lua`, `hypr/input.lua` (per machine), chromium flags, git config.
- Tahoe Link daemon (`~/Projects/tahoe-link`) — the `mehexi.phone` bar widget
  only works once that is installed too.
- Proton VPN CLI for the VPN menu/plugin (`protonvpn`).
