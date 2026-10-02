-- Hyprland settings the dock needs, installed as ~/.config/hypr/dock.lua and
-- pulled in from hyprland.lua with `pcall(require, "hypr.dock")`.
--
-- Blur behind the dock (animated.dock, layer namespace
-- "omarchy-animated-dock").
--
-- Hyprland's blur is a global switch: a layer rule opts a surface in, but
-- nothing renders while decoration.blur is off. Turning it on would normally
-- mean every window pays for blur too — Omarchy tags windows at 0.985/0.96
-- opacity, so they are translucent enough to trigger it for no visible gain.
-- The window rule below opts them all back out, leaving the dock as the only
-- surface actually blurred.
--
-- Both settings below are session-global: `decoration.blur` applies to
-- everything, and the blanket no_blur rule overrides any other rule (or
-- plugin) that wants a blurred window. Set DOCK_BLUR to false if you manage
-- window blur yourself, or just delete this file — the dock works fine
-- without it, it only loses the frosted background.

local DOCK_BLUR = true

if DOCK_BLUR then
  hl.config({
    decoration = {
      blur = {
        enabled = true,
        size = 8,
        passes = 3,
        noise = 0.02,
        vibrancy = 0.2,
      },
    },
  })

  hl.window_rule({ match = { class = ".*" }, no_blur = true })

  -- ignore_alpha keeps the blur from bleeding through the fully transparent
  -- parts of the dock's surface, so only the card itself is frosted.
  hl.layer_rule({ match = "omarchy-animated-dock", blur = true, ignore_alpha = 0.1 })
end
