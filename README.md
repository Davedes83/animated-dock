<a href='https://ko-fi.com/O3N726LJT4' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi5.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>

<img width="1224" height="1285" alt="preview" src="https://github.com/user-attachments/assets/45abebc9-e1e2-4d6f-8670-12016031ca2a" />

# Animated Dock

A fisheye dock for the Omarchy shell with macOS-style icon magnification, smooth animations, intelligent hide/reveal, window cycling, and full customization all in a Quickshell plugin.

The core feature is the continuous magnifier: as your pointer moves, icons flow around it with a smooth quadratic scale falloff, anchored to stay under your cursor without chasing. From there it adds:

Four edges with flexible positioning (start/center/end)
Smart hide: pressure-reveal hotspot with dodge for overlapping windows
Window controls: scroll to cycle through windows, click to minimize/focus/launch
Running indic

Right-click Omarchy menu opens the app's own context
menu 

## Requirements

- Omarchy (Hyprland + the Quickshell-based `omarchy-shell`)
- `jq` — used by the configurator

## Install

```bash
omarchy plugin add https://github.com/Davedes83/animated-dock --enable
```

That's the whole install: the repo root is the plugin. The dock appears with
a starter set matched to your machine — the Omarchy Menu, a file manager,
your default terminal, and your default browser — plus your running apps.
Two optional extras the plugin manager doesn't do:

- **Blur behind the dock** — copy [hypr/dock.lua](hypr/dock.lua) to
  `~/.config/hypr/dock.lua` and add
  `pcall(require, "hypr.dock")` to `~/.config/hypr/hyprland.lua`.
- **The configurator on your PATH** — the dock always runs its bundled
  copy, but for terminal use link it:
  `ln -s ~/.config/omarchy/plugins/animated.dock/bin/omarchy-dock-config ~/.local/bin/`

### From a checkout

```bash
git clone https://github.com/Davedes83/animated-dock ~/src/animated-dock
cd ~/src/animated-dock
./install.sh
```

`install.sh` is idempotent, backs up anything real it displaces, and takes
`--dry-run` if you want to see the plan first. Everything except
`shell.json` is a symlink back into this checkout; the dock's entry in
`shell.json` is merged in, staged through a temp file and only swapped in
once `jq` confirms the result still parses. An existing dock entry is never
overwritten unless you pass `--replace-config`.

## Configure

```bash
omarchy-dock-config --help      # or right-click the dock
```

The configurator writes straight into the dock's entry in `shell.json`, which
the shell re-reads on save — changes show up immediately, no restart.

Settings on the plugin entry:

| Key | Meaning |
|-----|---------|
| `items` | The pinned section; `{"spacer": true}` draws a divider |
| `edge` | Screen edge: `"bottom"` (default), `"top"`, `"left"`, or `"right"` — left/right give a vertical dock |
| `align` | Placement along that edge: `"center"` (default), `"start"`, or `"end"` |
| `iconSize` | Icon edge length in px |
| `zoom` | Fisheye strength (0–1; 0.45 default) |
| `zoomRaise` | How much of its growth an icon lifts out of the bar (0.5 default) |
| `magnify` | The continuous lens (default true) |
| `animation` | Reflow animation length, ms (default 110) |
| `spacing`, `padding` | In the card |
| `backgroundOpacity` | Card opacity (0–1) |
| `matchBarOpacity` | Sync the taskbar background opacity to `backgroundOpacity` (default `false`). Installed automatically on first use (see below) |
| `matchBarCorners` | Sync the taskbar's corner shape to the dock's (default `false`). Same automatic install (see below) |
| `glyphScale` | Nerd Font glyph ink as a fraction of the slot |
| `tiles`, `tileRadius`, `tileInset`, `tileOpacity` | Draw items as themed tiles |
| `border`, `cornerShape`, `cornerRadius` | Card chrome — `cornerShape` is `"rounded"`/`"square"`/`"pill"`; `cornerRadius` (px) applies when rounded |
| `glow` | Border glow halo (default `false`) |
| `glowAmount` | Glow strength, 0–1 (default 0.5) |
| `glowFocus` | `"full"` (default) owns the border, or `"bottom"` pushes the bloom onto the screen-edge side |
| `autohide` | `false` keeps the dock always visible (default true) |
| `dodge` | Intelli-hide from overlapping / fullscreen windows (default true) |
| `pressure` | Reveal delay collapses to zero on the edge hotspot (default true) |
| `revealDelay`, `hideDelay` | Hover-in and hover-out delays, ms |
| `hotspotFullWidth`, `hotspotHeight` | Size of the trigger zone on the edge |
| `showWhenEmpty` | Keep the card up on empty workspaces |
| `runningIndicator` | `"dot"` (default), `"line"`, or `"none"` |
| `showRunning` | The running-apps section (default true) |
| `labels` | Label pill beside the hovered item (default true) |
| `tintIcons`, `tintRunning`, `monochrome` | Icon colorization (defaults false / true / false) |
| `glyphColor` | `"accent"` or the default text color |
| `fullWidth`, `edgeGap` | Card length along the edge |

Item forms in `items[]`:

- `{ "desktop": "kitty" }` — launch a desktop entry
- `{ "exec": "cmd", "icon": "…", "label": "…" }` — run any command
- `{ "exec": "cmd", "glyph": "NICON" }` — a Nerd Font glyph instead of an icon
- `{ "showApps": true }` — the shell app menu
- `{ "trash": true }` — open the trash in the file manager
- `{ "spacer": true }` — divider rule
- `{ "when": "<cmd>" }` — show only while the command exits 0

### Programmatic CLI

The pin badge, context menu, and drag-to-reorder all persist through
`omarchy-dock-config` subcommands — one validated writer for shell.json
(indices 0-based):

```
omarchy-dock-config pin <appId> [index]
omarchy-dock-config unpin <index>
omarchy-dock-config move <from> <to>
omarchy-dock-config set-item <index> <json>
omarchy-dock-config add <json> [index]
omarchy-dock-config set <key> <json>     # dock-level; null unsets
omarchy-dock-config bar-opacity <n>      # taskbar opacity: 0.35 or 35
omarchy-dock-config matchbar-opacity <true|false>
omarchy-dock-config bar-corner             # re-mirror dock corner shape to taskbar
omarchy-dock-config matchbar-corners <true|false>
omarchy-dock-config ensure-bar           # idempotent taskbar support install
```

### Sync taskbar styling — automatic setup

Turning on **"Sync taskbar opacity"** or **"Sync taskbar corners"** makes the
taskbar mirror the dock: opacity as opaque as the dock's `backgroundOpacity`,
corners shaped like the dock's `cornerShape` / `cornerRadius`. The dock writes
those as `bar.backgroundOpacity` and `bar.cornerShape` / `bar.cornerRadius` in
`shell.json` — but only a taskbar that reads them reacts, and stock
`omarchy.bar` does not. So the first time a sync setting (or `bar-opacity`)
runs, the configurator installs the support itself:

1. If the active taskbar is the stock one, it clones it into
   `~/.config/omarchy/plugins/<user>.bar` and switches to it — the same
   `omarchy plugin clone` flow. (An existing clone is reused.)
2. It adds a small `backgroundOpacity` property and a `barCornerRadius`/
   `setBarCorners()` pair to that *user-owned* copy's `Bar.qml`, verified
   against exact anchors, backed up to `Bar.qml.bak`, and brace-checked; it
   refuses to touch an unrecognized bar rather than corrupt it. Each piece is
   added independently, so a clone that already has one feature just
   backfills the other.
3. It restarts the shell once so your cloned taskbar loads the new code with
   the setting applied.

That first run needs the one restart; from then on the toggles, slider, and
corner picker are instant. Nothing in the built-in taskbar is ever edited.
You can run `omarchy-dock-config ensure-bar` by hand any time to check or
re-run the install — it is idempotent and does nothing when support is
already present.

## Development

The shell watches `~/.config/omarchy/plugins`, but `inotifywait -r` does not
traverse symlinks — with the plugin directory linked into a checkout, apply
QML edits by hand with:

```bash
omarchy-shell shell rescanPlugins      # or: omarchy restart shell
```

Edits to `shell.json` need none of this — the shell hot-reloads that on save.

## Layout

```
./          the shell plugin itself (manifest.json + Dock.qml at the root,
            so the repo installs directly via `omarchy plugin add`)
bin/        omarchy-dock-config, the programmatic configurator
hypr/       dock.lua — blur and layer rules for Hyprland
config/     shell.dock.json — the dock entry's style defaults for shell.json
            (items are resolved per user at install: Menu, Files, the
            default terminal and browser)
```

The heat is in `Dock.qml`: a 16 ms loop eases each cell's scale toward the
lens targets (narrow quadratic zoom about `pointerMain`, reported by each
dock window's `HoverHandler`, mapped to row coordinates) while keeping
positions, the card and the border frozen.  `DockItem.qml` places and
dresses each cell.
`RunningModel.qml` derives the running section, `ContextMenu.qml` the
right-click menu.

## Uninstall

```bash
./uninstall.sh                 # keeps your dock settings in shell.json
./uninstall.sh --purge-config  # drops them too
```

It only removes symlinks that point back into this checkout, so anything you
installed another way is left alone.

## License

MIT
