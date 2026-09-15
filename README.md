# Animated Dock

A macOS-style **fisheye** dock for the [Omarchy](https://omarchy.org/) shell,
functionally equivalent to [dash2dock-lite](https://github.com/icedman/dash2dock-lite)
and cast in a third-party Quickshell plugin (`animated.dock`), in the spirit
and architecture of the `rdf.dock` Omarchy dock.

The signature behaviour is the *continuous* magnifier: every pointer move
inside the dock re-flows the icons in a lens around the pointer. Each icon's
scale is a quadratic falloff from the pointer (`scale = 1 + zoom·p²`), the
layout is anchored on the most magnified icon so the pointer never chases a
target, and icons lift out of the bar as they grow. The flow animates through
`Behaviour` bindings, so a stationary pointer settles and a moving one chases
smoothly.

Also on the dash2dock feature list:

- **All four edges** (`bottom` / `top` / `left` / `right`), aligned to the
  start, centre, or end of the edge.
- **Edge-pressure reveal + intelli-hide**: a thin hotspot on the edge slides
  the dock out (`pressure` collapses the reveal delay to zero); while
  `dodge` is on, the dock stays hidden whenever a window — or a fullscreen
  window — overlaps the card's on-screen area.
- **Scroll-to-cycle**: the wheel over a running icon steps through its
  windows, MRU-first, with the label flashing the current title.
- **Click-to-toggle-minimize**: a running and focused icon minimizes the app;
  a click on a running-but-unfocused one focuses its most recent window; not
  running launches.
- **Running indicators** (`dot` / `line` / `none`), lit brighter for the
  focused app, plus a count badge on grouped windows.
- **Pinned + running sections**, split by an automatic divider; running apps
  derive live from the compositor and are never written to config.
- **Drag-to-reorder**, and drag across the divider to pin / unpin (the
  divider doubles as the pinned/running boundary).
- **Icon tinting and mono**: app icons can be colorized to the theme accent
  (`tintIcons`, `tintRunning`, `monochrome`), so arbitrary apps sit next to
  curated Nerd Font glyphs as one set.
- **Multi-monitor**: the dock parks on the monitor you ask for, and a hover
  on the hotspot of any monitor summons it there.
- **IPC** for keybindings: `omarchy-shell animated.dock toggle`.

Right-click (or click-and-hold, for trackpads) opens the app's own context
menu — its **Desktop Actions** when it ships any (a browser's private
window…), New Window, Pin/Unpin, per-window focus, and Close All. Clicking
anywhere else, picking a row, or hovering another icon dismisses it.

## Requirements

- Omarchy (Hyprland + the Quickshell-based `omarchy-shell`)
- `jq` — used by the configurator

## Install

```bash
omarchy plugin add https://github.com/<you>/animated-dock --enable
```

That's the whole install: the repo root is the plugin. The dock appears with
the starter items from `config/shell.dock.json` plus your running apps.
Two optional extras the plugin manager doesn't do:

- **Blur behind the dock** — copy [hypr/dock.lua](hypr/dock.lua) to
  `~/.config/hypr/dock.lua` and add
  `pcall(require, "hypr.dock")` to `~/.config/hypr/hyprland.lua`.
- **The configurator on your PATH** — the dock always runs its bundled
  copy, but for terminal use link it:
  `ln -s ~/.config/omarchy/plugins/animated.dock/bin/omarchy-dock-config ~/.local/bin/`

### From a checkout

```bash
git clone https://github.com/<you>/animated-dock ~/src/animated-dock
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
| `glyphScale` | Nerd Font glyph ink as a fraction of the slot |
| `tiles`, `tileRadius`, `tileInset`, `tileOpacity` | Draw items as themed tiles |
| `border`, `cornerRadius` | Card chrome |
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
```

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
config/     shell.dock.json — the starter dock entry for shell.json
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