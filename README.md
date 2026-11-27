# omarchy-dotfiles

My Omarchy desktop, installable on any Omarchy 4 machine in one command.

A frosted rail down the left edge that joins the screen frame, a quarter-circle
control corner, a search-first menu, recessed windows and a fastfetch dashboard —
[denon's Pebble Shell](https://github.com/denonmaryland/omarchy-dotfiles), with my
own lock screen, phone panel and a handful of fixes on top.

## Install

On a machine running Omarchy 4 (4.0.6 or newer; built on 4.5):

```bash
curl -fsSL https://raw.githubusercontent.com/mehexi/omarchy-dotfiles/main/bootstrap.sh | bash
```

That clones this repo to `~/.local/share/omarchy-dotfiles` and runs `install.sh`.
It lists what it will change and asks once before touching anything.

Options pass straight through:

```bash
# skip the themes (they are ~1.7 GB of clones)
curl -fsSL https://raw.githubusercontent.com/mehexi/omarchy-dotfiles/main/bootstrap.sh | bash -s -- --skip-themes

# skip the MacTahoe icon theme too, and don't ask
curl -fsSL https://raw.githubusercontent.com/mehexi/omarchy-dotfiles/main/bootstrap.sh | bash -s -- --skip-themes --skip-icons --yes
```

Already cloned it? `./install.sh` does the same thing. Re-running is safe — it
backs up again, copies again, and skips work already done.

**Everything it replaces is backed up first** to
`~/.config/omarchy-dotfiles-backup/<timestamp>/`. To undo, copy those files back
and run `hyprctl reload && omarchy restart shell`.

## What it touches

| | |
|---|---|
| `~/.config/omarchy/` | shell plugins, bar layout, dock, bar scripts, hooks, extensions, branding |
| `~/.config/hypr/` | `bindings`, `brave-tabs`, `carousel`, `glass`, `hyprland`, `input`, `looknfeel`, `recessed_windows`, `tricky-tiles` |
| `~/.config/` | fastfetch, foot, alacritty, kitty, ghostty, btop, tmux |
| `~/.local/` | `omarchy-glass`, `omarchy-recess`, `denon-agent-usage`, `touchpad-control`, and the `denon-*` / `hypr-*` scripts |
| packages | `qt6-5compat` if missing (the rail draws its edges with it) |

**Never touched:** `hypr/monitors.lua` and `hypr/autostart.lua`. Those describe a
particular machine, so your displays and startup apps survive the install.

Three plugins are installed from their own repos rather than vendored here —
Theme Studio, Tricky Tiles and Softly (see `externals.txt`). Files of theirs that
I changed live in `patches/` and are laid back over the fresh clone.

## What I changed in denon's work

- **Clock.** The rail clock reads as one clock: hour and minute at 1.12×, a 2px
  rounded rule under the hour, and any alphabetic line (AM/PM, a weekday) dropped
  back to 0.78× at 0.55 opacity as a label.
- **No battery on a desktop.** UPower hands out a placeholder battery device on
  machines that have none, which the control corner painted as a permanent
  "On battery · 0%". Now gated on `isLaptopBattery`; a laptop still shows its pack.
- **The phone in its place.** With no battery, that slot in the fan shows the
  linked Android phone instead — name, charge and charging state from
  [tahoe-link](https://github.com/mehexi)'s state file, in the battery's own type
  scale. Click it for the full card.
- **Brightness over DDC.** The corner read brightness with `brightnessctl`, which
  with no device argument returns the first entry in `/sys/class/backlight` — on a
  desktop that is often a NIC LED, so it always showed 0. It now uses
  `omarchy-brightness-display`, which resolves the focused monitor and reads it
  over DDC/CI, the same path the setter already wrote through.
- **Wallhaven wallpapers.** Theme Studio's catalog now comes from
  [Wallhaven](https://wallhaven.cc) instead of Openverse — anime category, sfw +
  sketchy, no API key needed. The JSON contract is unchanged, so the panel didn't
  need rewriting. Tunable with `WALLHAVEN_PURITY`, `WALLHAVEN_CATEGORIES`,
  `WALLHAVEN_ATLEAST`; an optional key in `~/.config/omarchy/wallhaven-api-key`
  unlocks nsfw. Wallhaven states no licence for uploads, so saved wallpapers are
  credited by source link rather than by licence.
- **My lock screen.** `mehexi.lock` replaces Hello Lock — a macOS-style clock
  state with avatar and password field, and the display stays on while locked.
- **Glass.** Window opacity raised to 0.96 active / 0.93 inactive; the wallpaper
  was bleeding through terminal text.
- **Stay-awake indicator** removed from the rail. The feature still works from the
  control corner; it just no longer keeps an icon there.

## Keeping it up to date

On this PC, after changing anything:

```bash
./sync.sh          # copy ~/.config and ~/.local into the repo
git add -A && git commit -m "..." && git push
```

`sync.sh` deliberately leaves out `monitors.lua`, `autostart.lua`, the dead
pre-Lua `hypr/*.conf` leftovers, every `.git` inside a cloned plugin, and the
three upstream plugins above.

## Credits

The look is overwhelmingly [denonmaryland/omarchy-dotfiles](https://github.com/denonmaryland/omarchy-dotfiles)
(MIT), itself built on [Omarchy](https://omarchy.org) (MIT). Full attribution in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
