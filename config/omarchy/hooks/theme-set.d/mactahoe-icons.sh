#!/bin/bash
# Keep the MacTahoe icon theme after Omarchy theme switches (which set the
# theme's own icons.theme). Change ICON_THEME to MacTahoe-green-dark etc.
ICON_THEME=MacTahoe-dark
gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME"
