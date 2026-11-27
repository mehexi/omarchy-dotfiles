# Third-party notices

This repository is a personal desktop configuration. Most of what it contains is
other people's work, redistributed here under the terms below. My own changes are
in `LICENSE`.

## Omarchy

<https://omarchy.org> — MIT. Many plugins under `config/omarchy/plugins/` began as
clones of Omarchy's built-in plugins (`omarchy plugin clone`) and keep their
structure and much of their code. Anything named `omarchy.*` upstream belongs to
the Omarchy project.

## denonmaryland/omarchy-dotfiles

<https://github.com/denonmaryland/omarchy-dotfiles> — MIT. The bulk of the look in
this repo is denon's "Pebble Shell" work, vendored here with small changes:

- every `config/omarchy/plugins/denon.*` plugin (the rail, control corner, menu,
  studio drawer, glass and depth controls, restyled widgets and panels)
- the Hyprland Lua files: `bindings`, `brave-tabs`, `carousel`, `glass`,
  `hyprland`, `input`, `looknfeel`, `recessed_windows`, `tricky-tiles`
- `config/fastfetch/` (config and dashboard)
- `config/foot/foot.ini`
- everything under `local/` (`omarchy-glass`, `omarchy-recess`,
  `denon-agent-usage`, `touchpad-control`, and the `denon-*` / `hypr-*` scripts)

Changes made here are noted in the README under "What I changed in denon's work".

## Theme Studio, Tricky Tiles, Softly

<https://github.com/denonmaryland/omarchy-theme-studio>,
<https://github.com/denonmaryland/omarchy-tricky-tiles>,
<https://github.com/denonmaryland/omarchy-softly> — MIT. **Not vendored.**
`install.sh` installs them from their own repositories (see `externals.txt`).
Two Theme Studio files are modified afterwards from `patches/`; the modified
copies there are derivatives of denon's MIT-licensed originals.

## Lucide

<https://lucide.dev> — ISC. The icon sets in `config/omarchy/plugins/denon.menu/icons/`
and `config/omarchy/plugins/denon.tray/icons/`, each with its own `LICENSE` file.

## MacTahoe icon theme

<https://github.com/vinceliuice/MacTahoe-icon-theme> — GPL-3.0. Not vendored;
`install.sh` clones and installs it, then recolours the folder SVGs.

## Themes

`themes.txt` lists Omarchy themes cloned from their own repositories at install
time. They are not vendored and remain the property of their creators.
