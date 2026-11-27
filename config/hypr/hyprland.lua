-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })

-- Launchpad (mehexi.launchpad): frosted full-screen backdrop, shell animates itself.
hl.layer_rule({ match = { namespace = "mehexi-launchpad" }, blur = true, ignore_alpha = 0.3, no_anim = true, animation = "none" })
-- Control center (mehexi.control-center) glass card. Omarchy's own panels share
-- this namespace but have opaque cards, so only translucent ones look frosted.
hl.layer_rule({ match = { namespace = "omarchy-keyboard-panel" }, blur = true, ignore_alpha = 0.3 })

-- Tahoe Link screen mirroring (scrcpy): docked on the right edge at full height, on
-- the workspace it opens on. These rules just place it roughly on open; tahoe-link
-- then sizes it to the phone's exact shape (and on rotation) and, while its workspace
-- is on screen, widens the right gap so tiled windows fill the rest.
o.window("scrcpy", {
  float = true,
  size = { "(monitor_h-50)*0.45", "monitor_h-50" },
  move = { "monitor_w-window_w-12", "38" },
})

-- Dock (mehexi.dock): frosted pill on the bottom edge. Same deal as the
-- Launchpad above — Hyprland blurs what's under the layer above alpha 0.3,
-- and the plugin keeps its glass tint above that.
hl.layer_rule({ match = { namespace = "mehexi-dock" }, blur = true, ignore_alpha = 0.3 })
