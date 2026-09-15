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
require("hypr.parallax-backgrounds")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })

-- Adjust floating terminal / window size so TUI apps like btop fit properly on scaled displays
o.window({ tag = "floating-window" }, { size = { 1000, 650 } })
o.window("org.omarchy.btop", { size = { 1000, 650 } })

-- All windows completely opaque when focused (1.0 active, 0.96 inactive)
o.window({ tag = "default-opacity" }, { opacity = "1.0 0.96" })
