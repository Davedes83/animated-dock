import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Animated Dock — a fisheye-magnifying auto-hidden dock for the Omarchy
// shell, functionally equivalent to dash2dock-lite.
//
// The signature behaviour is the *continuous* magnifier: every pointer move
// inside the dock re-flows the icons in a lens around the pointer (dash2dock
// calls this the "magnify" animator). Each icon's scale is a quadratic
// falloff from the pointer's position; the layout is anchored on the most
// magnified icon so the pointer never chases a target, and the icons lift
// out of the dock as they grow. The flow animates through Behaviour
// bindings rather than a manual loop, so a stationary pointer settles and a
// moving one chases smoothly.
//
// Also on the dash2dock feature list: all four edges with alignment, the
// edge-pressure reveal plus intelli-hide from overlapping windows ("dodge"),
// scroll-to-cycle windows, click-to-toggle-minimize, running indicators,
// pinned + running sections split by a divider, drag-to-reorder /
// drag-to-pin, icon tinting and mono, multi-monitor support, and an IPC
// surface for summoning.
//
// The window parks just past its screen edge and slides back in, exactly as
// the parent dock does: keeping the layer surface and its scene graph alive
// makes a reveal a margin change instead of a surface rebuild.
//
// Configuration is this plugin's own entry in ~/.config/omarchy/shell.json,
// which the shell re-reads on save, so edits apply live:
//
//   {
//     "id": "animated.dock",
//     "edge": "bottom", "align": "center", "iconSize": 44, "zoom": 0.45,
//     "magnify": true, "spacing": 4, "padding": 8,
//     "autohide": true, "dodge": true, "pressure": true,
//     "border": true, "borderOpacity": 1.0, "glow": false,
//     "glowAmount": 0.5, "glowFocus": "full",
//     "items": [ { "desktop": "kitty" }, { "desktop": "steam" } ]
//   }
//
// Item forms:
//   { "desktop": "chromium" }          launch a desktop entry
//   { "exec": "cmd", "icon": "...", "label": "..." }  run any command
//   { "exec": "cmd", "glyph": "NICON" } a Nerd Font glyph instead of an icon
//   { "showApps": true }               the shell app menu
//   { "trash": true }                  open the trash in the file manager
//   { "spacer": true }                 divider rule
//   { "when": "<cmd>" }                conditional presence
//
// Colors, radii, fonts and spacings come from the shell's Color/Style
// singletons, so the dock re-themes with `omarchy theme set` live.
Item {
  id: root

  // Injected by the shell's panel loader.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "animated.dock"

  // The bundled configurator is the one writer for shell.json. Resolve the
  // binary next to this QML file (Omarchy 4.0.3 strips __sourceDir from the
  // manifest handed to third-party plugins).
  readonly property string configCmd: manifest && manifest.__sourceDir
    ? Util.shellQuote(String(manifest.__sourceDir) + "/bin/omarchy-dock-config")
    : Util.shellQuote(String(Qt.resolvedUrl("bin/omarchy-dock-config")).replace(/^file:\/\//, ""))

  readonly property string homeDir: Quickshell.env("HOME")

  // Omarchy 4.0.3 hardened the plugin host: the injected `shell` facade no
  // longer exposes shellConfig, so this plugin's own entry in
  // ~/.config/omarchy/shell.json is not reachable through it. Watch the file
  // directly and read the entry from there instead. Once the shell restores
  // shellConfig, the primary path below wins again.
  property var fallbackConfig: ({})

  function parseFallbackConfig(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      var list = parsed && Array.isArray(parsed.plugins) ? parsed.plugins : []
      for (var i = 0; i < list.length; i++) {
        var entry = list[i]
        if (Util.isPlainObject(entry) && String(entry.id || "") === root.pluginId) {
          root.fallbackConfig = entry
          return
        }
      }
    } catch (e) {
      console.warn("animated.dock: shell.json read failed:", e)
    }
    root.fallbackConfig = ({})
  }

  // This plugin's entry in shell.json plugins[]. Reading shell.shellConfig
  // here is what makes the binding re-evaluate on every shell.json save; the
  // FileView fallback keeps it live under the 4.0.3 facade.
  readonly property var config: {
    var list = shell && shell.shellConfig && Array.isArray(shell.shellConfig.plugins)
      ? shell.shellConfig.plugins
      : []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i]
      if (Util.isPlainObject(entry) && String(entry.id || "") === root.pluginId) return entry
    }
    return root.fallbackConfig
  }

  // `omarchy plugin add` clones the repo but never runs install.sh (the one
  // thing that resolved the per-user starter apps), so a brand-new shell.json
  // entry lands with no `items` array: no pinned apps, and no Omarchy Menu
  // icon — which is also the only right-click path to the Settings popup.
  // Seed the starter set exactly once, in the background, as soon as the
  // entry is known to lack one. The write goes through the configurator (the
  // single writer for shell.json); the shell hot-reloads on save and the four
  // default apps appear live. Deliberately leaving an empty pinned section
  // (items: []) is respected — only a missing key is ever seeded.
  property bool seedStarted: false

  function maybeSeedDefaults() {
    if (root.seedStarted) return
    var c = root.config
    if (!Util.isPlainObject(c) || String(c.id || "") !== root.pluginId) return
    if (Array.isArray(c.items)) return
    root.seedStarted = true
    Util.execDetached(configCmd + " seed-defaults")
  }

  // Fires once the entry shows up, whether via shell.shellConfig or the
  // FileView fallback; the seedStarted guard keeps it to one attempt.
  onConfigChanged: root.maybeSeedDefaults()

  FileView {
    id: dockConfigFile
    path: root.homeDir + "/.config/omarchy/shell.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.parseFallbackConfig(text())
    onLoadFailed: function(error) {
      console.warn("animated.dock: could not watch shell.json: " + error)
    }
    onFileChanged: reload()
  }

  function num(key, fallback) {
    var n = Number(root.config[key])
    return isFinite(n) && n > 0 ? n : fallback
  }

  function flag(key, fallback) {
    var v = root.config[key]
    return typeof v === "boolean" ? v : fallback
  }

  // Like num(), but zero is a legitimate value — icons packed edge to edge
  // is a real choice, so spacing and padding accept it.
  function num0(key, fallback) {
    var n = Number(root.config[key])
    return isFinite(n) && n >= 0 ? n : fallback
  }

  // A 0–1 fraction, but anything above 1 is read as a percentage. "90" is a
  // far more natural thing to type than "0.9".
  function fraction(key, fallback) {
    var n = Number(root.config[key])
    if (!isFinite(n) || n < 0) return fallback
    if (n > 1) n = n / 100
    return Math.min(1, n)
  }

  // ----------------------------------------------------------- edge terms
  //
  // `edge` is the screen edge the dock lives on; `align` places it along
  // that edge. Everything below is written in terms of a *main* axis (along
  // the edge: the flow of icons) and a *cross* axis (out from the edge:
  // card thickness, label band, reveal slide), so a vertical dock is the
  // same layout rotated.
  readonly property string edge: {
    var e = String(config.edge || "").toLowerCase()
    return (e === "top" || e === "left" || e === "right") ? e : "bottom"
  }
  readonly property string align: {
    var a = String(config.align || "").toLowerCase()
    if (a === "left" || a === "top") return "start"
    if (a === "right" || a === "bottom") return "end"
    return (a === "start" || a === "end") ? a : "center"
  }
  readonly property bool vertical: edge === "left" || edge === "right"
  // On left/top the screen edge is at the window's origin, so the edge-gap
  // strip comes *before* the card in window coordinates.
  readonly property bool edgeFirst: edge === "left" || edge === "top"

  readonly property var items: Array.isArray(config.items) ? config.items : []

  readonly property bool autohide: flag("autohide", true)
  readonly property bool dodge: flag("dodge", true)
  // Edge-pressure reveal: with `pressure` on, the reveal delay collapses to
  // zero so merely brushing the edge snaps the dock out — dash2dock's
  // "pressure sense". Off, the reveal waits the configured revealDelay.
  readonly property bool pressure: flag("pressure", true)

  readonly property bool showRunning: flag("showRunning", true)
  readonly property string runningIndicator:
    (config.runningIndicator === "line" || config.runningIndicator === "none")
      ? String(config.runningIndicator) : "dot"

  readonly property bool tintIcons: flag("tintIcons", false)
  readonly property bool tintRunning: flag("tintRunning", true)
  readonly property bool monochrome: flag("monochrome", false)

  readonly property bool labels: flag("labels", true)
  readonly property bool magnify: flag("magnify", true)
  readonly property bool showWhenEmpty: flag("showWhenEmpty", false)
  readonly property bool hotspotFullWidth: flag("hotspotFullWidth", false)
  readonly property int hotspotHeight: Math.max(1, Style.space(num("hotspotHeight", 2)))
  readonly property int revealDelay: pressure ? 0 : Math.round(num("revealDelay", 90))
  readonly property int hideDelay: Math.round(num("hideDelay", 300))

  // Fisheye tunables.
  readonly property real zoom: fraction("zoom", 0.45)
  // How much of its growth an icon "lifts" out of the bar (dash2dock
  // ANIM_ICON_RAISE is 0.5).
  readonly property real zoomRaise: fraction("zoomRaise", 0.5)
  // Animation length of the reflow, ms.
  readonly property int animMs: Math.round(num0("animation", 110))

  // The slider's 0–1 override is applied on top of the theme's border color
  // (RGB preserved, alpha forced), so the label matches what renders.
  readonly property real borderOpacity: fraction("borderOpacity", 1.0)
  readonly property var dockBorder: flag("border", true)
    ? (root.borderOpacity < 1
      ? withBorderOpacity(Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2))), root.borderOpacity)
      : Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2))))
    : Border.none()
  readonly property var tipBorder: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, Math.max(1, Style.space(1)))

  // Border glow. A halo drawn behind the card from the border's own ring, in
  // the theme's opaque popup border colour (so it survives `borderOpacity`
  // and even stands alone when the hairline is off). `glowFocus` picks how
  // the halo is weighted: "full" shows it evenly all round, "bottom" pushes
  // the extra bloom onto the side of the border that faces the screen edge —
  // an underglow look for a dock, strongest at the docked edge, normal up
  // top — and "top" shifts it the other way. Off by default.
  readonly property bool glowEnabled: flag("glow", false)
  readonly property real glowStrength: fraction("glowAmount", 0.5)
  // "bottom" pushes the halo toward the docked edge (the underglow look),
  // "top" toward the opposite side; anything else keeps it evenly all round.
  readonly property real glowShift: String(config.glowFocus || "") === "bottom" ? 1
    : String(config.glowFocus || "") === "top" ? -1 : 0
  readonly property color glowColor: Border.color(
    Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2))))
  // How far past the card the halo may bloom; the window reserves this much
  // room so the glow is never clipped by the surface edge.
  readonly property int glowRoom: glowEnabled ? Math.max(1, Style.space(10)) : 0
  // Extra room along the edge: both flanks for a centred card, one (the
  // non-corner side) for start/end. A full-width card ends at the screen
  // corners, so any extra would be off-screen — none.
  readonly property int glowMainExtra: (glowRoom === 0 || fullWidth) ? 0
    : (align === "center" ? glowRoom * 2 : glowRoom)
  // Inward room on the cross axis (the side that faces the desktop). The
  // docked-edge side already has the edge strip to glow across.
  readonly property int glowCrossExtra: glowRoom
  readonly property real glowShiftX: vertical ? (edge === "right" ? glowShift : -glowShift) : 0
  readonly property real glowShiftY: vertical ? 0 : (edge === "bottom" ? glowShift : -glowShift)

  // Re-index the spec's colours with a forced alpha on the flat fill; a
  // gradient keeps its stops, each tinted to the same opacity. Rectangle.border
  // in Qt6 renders sub-opaque border colours correctly, so the spec is left on
  // the cheap native path.
  function withBorderOpacity(spec, opacity) {
    var color = Util.alpha(Border.color(spec), opacity)
    if (spec.gradient && spec.gradient.enabled) {
      var stops = []
      for (var i = 0; i < spec.gradient.colors.length; i++)
        stops.push(Util.alpha(spec.gradient.colors[i], opacity))
      return { color: color, widths: spec.widths, gradient: { colors: stops, angle: spec.gradient.angle, enabled: true } }
    }
    return { color: color, widths: spec.widths, gradient: spec.gradient }
  }

  RunningModel {
    id: running
    dock: root
    pinnedItems: root.items
  }

  ContextMenu {
    id: contextMenu
    dock: root
  }

  DockSettings {
    id: settingsWindow
    dock: root
  }

  readonly property bool menuOpen: contextMenu.open
  readonly property bool settingsOpen: settingsWindow.open
  readonly property int menuIndex: menuOpen && contextMenu.anchorCell ? contextMenu.anchorCell.index : -1
  // Anything that holds the dock revealed while it's up.
  readonly property bool popupOpen: menuOpen || settingsOpen

  function openMenu(cell) {
    if (!cell || cell.isRule) return
    if (menuOpen && cell.index === menuIndex) {
      contextMenu.close()
      return
    }
    contextMenu.openFor(cell)
  }

  function closeMenu() { contextMenu.close() }

  // After a click-and-hold opens the menu, continued motion across the
  // card's inward face is a menu gesture, not a drag — the cell disables its
  // DragHandler for the rest of the press.
  function menuSweep(cell, window, wx, wy) {
    var across = vertical ? wx : wy
    return edgeFirst ? across > cardInnerFace : across < cardInnerFace
  }

  // Icon hover while a popup is up: moving onto another icon dismisses the
  // menu, so the pointer never has to leave the dock to get out of a menu it
  // opened by mistake.
  function onIconHovered(cell) {
    if (dragging || !cell || cell.isRule) return
    if (menuOpen) {
      if (cell.index !== menuIndex) closeMenu()
    }
  }

  // A popup holds the dock open the same way IPC show() does.
  function holdForPopup() {
    held = true
    hideTimer.stop()
  }

  function releasePopup() {
    if (popupOpen) return
    held = false
    if (!wantOpen) hideTimer.restart()
  }

  // ContextMenu.close() calls this after dropping `open`, so the popup hold
  // releases on the same tick the menu goes away. DockSettings.close() does
  // the same.
  function menuReleased() { releasePopup() }
  function popupReleased() { releasePopup() }

  // A settings UI writes through the bundled configurator, which stages a
  // mutation of shell.json and applies it atomically; the shell hot-reloads
  // on save, so the change lands live. Values must be valid JSON literals.
  function applySetting(key, jsonValue) {
    Util.execDetached(configCmd + " set " + Util.shellQuote(key) + " " + Util.shellQuote(String(jsonValue)))
  }

  // Same references in the same order.
  function sameWindows(a, b) {
    if (a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
    return true
  }

  property var cells: []
  function registerCell(cell) { cells.push(cell) }
  function unregisterCell(cell) {
    var i = cells.indexOf(cell)
    if (i >= 0) cells.splice(i, 1)
  }
  function cellAt(index) {
    for (var i = 0; i < cells.length; i++)
      if (cells[i].index === index) return cells[i]
    return null
  }

  // --------------------------------------------------------------- pinning

  function requestPin(item) {
    if (!item || item.__running !== true) return
    var idx = items.length
    Util.execDetached(configCmd + " pin " + Util.shellQuote(String(item.appId)) + " " + idx)
  }

  function requestUnpin(item) {
    var idx = items.indexOf(item)
    if (idx < 0) return
    Util.execDetached(configCmd + " unpin " + idx)
  }

  // The Apps (showApps) icon's Settings row: open the dock's own settings
  // window, anchored to the icon that summoned it.
  function openSettings(cell) {
    if (!cell) return
    if (settingsOpen && settingsWindow.anchorCell === cell) {
      settingsWindow.close()
      return
    }
    settingsWindow.openFor(cell)
  }

  function windowsFor(item) { return running.windowsFor(item) }

  readonly property var displayItems: {
    var out = shownItems.slice()
    if (showRunning) {
      var ex = running.extras
      if (ex.length > 0) {
        out.push({ __divider: true })
        out = out.concat(ex)
      }
    }
    return out
  }

  // ---------------------------------------------------- conditional items
  //
  // An item may carry a `when` command; it occupies a slot only while that
  // command exits 0. Conditions are evaluated in a single batched
  // subprocess, one line of output per condition.

  readonly property var conditionIndices: {
    var out = []
    for (var i = 0; i < items.length; i++) {
      var it = items[i]
      if (Util.isPlainObject(it) && typeof it.when === "string" && it.when.trim() !== "") out.push(i)
    }
    return out
  }

  property var conditionResults: ({})

  function conditionMet(index) {
    var v = conditionResults[index]
    return v === undefined ? true : v === true
  }

  readonly property var shownItems: {
    if (conditionIndices.length === 0) return items
    var out = []
    for (var i = 0; i < items.length; i++) if (conditionMet(i)) out.push(items[i])
    return out
  }

  readonly property bool active: displayItems.length > 0

  // Evaluations run in a batched subprocess, one line of output per
  // condition. The indices being evaluated are snapshotted when the run
  // starts and every run carries a generation: a config reload (or a timer
  // tick) that changes the set mid-run bumps the generation, and the
  // completion handler drops any run whose snapshot is no longer current
  // instead of mapping stale stdout onto a different item.
  property int conditionGeneration: 0

  function evaluateConditions() {
    if (conditionIndices.length === 0) return
    var idx = conditionIndices.slice()
    conditionGeneration++
    conditionProc.generation = conditionGeneration
    conditionProc.pendingIndices = idx
    conditionProc.pending = []
    var lines = []
    for (var i = 0; i < idx.length; i++) {
      var cmd = String(items[idx[i]].when)
      lines.push("if { " + cmd + " ; } >/dev/null 2>&1; then echo 1; else echo 0; fi")
    }
    conditionProc.command = ["bash", "-lc", lines.join("\n")]
    conditionProc.running = true
  }

  onConditionIndicesChanged: evaluateConditions()

  Process {
    id: conditionProc
    // Snapshot of the items[] indices this run answers for, plus the
    // generation of the evaluateConditions() call that started it.
    property var pendingIndices: []
    property int generation: 0
    property var pending: []

    stdout: SplitParser {
      onRead: function(line) {
        conditionProc.pending.push(String(line).trim() === "1")
      }
    }

    onRunningChanged: {
      if (running) return
      // A newer evaluateConditions() superseded this run; its stdout maps to
      // a previous item set and must not touch the current results.
      if (conditionProc.generation !== root.conditionGeneration) return
      var idx = conditionProc.pendingIndices
      for (var i = 0; i < idx.length; i++) {
        var resolved = conditionProc.pending.length > i ? conditionProc.pending[i] : true
        if (root.conditionResults[idx[i]] !== resolved) {
          var next = {}
          for (var k in root.conditionResults) next[k] = root.conditionResults[k]
          next[idx[i]] = resolved
          root.conditionResults = next
        }
      }
    }
  }

  Timer {
    running: root.conditionIndices.length > 0
    interval: 5000
    repeat: true
    triggeredOnStart: true
    onTriggered: root.evaluateConditions()
  }// ----------------------------------------------------------------- drag
  //
  // Cells are positioned by cellPos rather than a Row/Column, so the layout
  // can open a live gap at the insertion point while something is dragged.
  // All drag coordinates are main-axis: x on a horizontal dock, y on a
  // vertical one. Dragging disables the fisheye — dash2dock's _dragging
  // noAnimation mode — so the dragged cell glues to the pointer while the
  // others slide aside over the base flow.

  property int dragIndex: -1
  property real dragPointer: 0
  property real dragGrabD: 0
  readonly property bool dragging: dragIndex >= 0

  function mainCoord(cell, sceneX, sceneY) {
    var p = cell.parent.mapFromItem(null, sceneX, sceneY)
    return vertical ? p.y : p.x
  }

  function beginDrag(cell, sceneX, sceneY) {
    contextMenu.close()
    settingsWindow.close()
    var r = mainCoord(cell, sceneX, sceneY)
    dragGrabD = r - (vertical ? cell.y : cell.x)
    dragPointer = r
    dragIndex = cell.index
    hoveredLabel = ""
  }

  function updateDrag(cell, sceneX, sceneY) {
    dragPointer = mainCoord(cell, sceneX, sceneY)
  }

  // Insertion slot among the un-dragged cells, from the dragged cell's
  // centre against the base-flow centres.
  readonly property int dropIndex: {
    if (!dragging) return -1
    var draggedCenter = dragPointer - dragGrabD + cellSize(displayItems[dragIndex]) / 2
    var x = 0
    var flow = 0
    var result = 0
    for (var i = 0; i < displayItems.length; i++) {
      if (i === dragIndex) continue
      var w = cellSize(displayItems[i])
      if (draggedCenter > x + w / 2) result = flow + 1
      x += w + gap
      flow++
    }
    return result
  }

  // Main-axis offset for every cell: cumulative flow positions, with a
  // dragged-cell-sized gap held open at dropIndex.
  readonly property var cellPos: {
    var xs = new Array(displayItems.length)
    var x = 0
    var flow = 0
    var dw = dragging ? cellSize(displayItems[dragIndex]) + gap : 0
    for (var i = 0; i < displayItems.length; i++) {
      if (i === dragIndex) { xs[i] = 0; continue }
      xs[i] = x + (dragging && flow >= dropIndex ? dw : 0)
      x += cellSize(displayItems[i]) + gap
      flow++
    }
    return xs
  }

  function endDrag() {
    if (!dragging) return
    var s = dragIndex
    var t = dropIndex
    dragIndex = -1

    var item = displayItems[s]
    if (!Util.isPlainObject(item)) return

    // Zone boundary: how many un-dragged cells are pinned items.
    var pinnedFlow = 0
    for (var i = 0; i < displayItems.length; i++) {
      if (i === s) continue
      if (items.indexOf(displayItems[i]) >= 0) pinnedFlow++
    }

    var insertAt = items.length
    var flow = 0
    for (var j = 0; j < displayItems.length; j++) {
      if (j === s) continue
      if (flow === t) {
        var idx = items.indexOf(displayItems[j])
        if (idx >= 0) insertAt = idx
        break
      }
      flow++
    }

    var from = items.indexOf(item)
    if (from >= 0) {
      if (t > pinnedFlow) {
        Util.execDetached(configCmd + " unpin " + from)
      } else {
        var to = insertAt > from ? insertAt - 1 : insertAt
        if (to !== from)
          Util.execDetached(configCmd + " move " + from + " " + to)
      }
    } else if (item.__running === true && t <= pinnedFlow) {
      Util.execDetached(configCmd + " pin "
        + Util.shellQuote(String(item.appId)) + " " + insertAt)
    }
  }

  function cancelDrag() { dragIndex = -1 }

  // -------------------------------------------------------------- fisheye
  //
  // The lens. Every mouse move inside the dock reports the pointer's
  // main-axis position in *row coordinates* (each dock window maps it through
  // its own row, and every row is laid out identically, so the number is
  // shared). From that position each cell gets a scale:
  //
  //     scale = 1 + zoom * p²,   p = 1 - |distance| / T
  //
  // a quadratic falloff out to T ≈ 2.2 slots. The layout is anchored on the
  // most magnified cell — it keeps its resting centre — and each neighbour
  // is pushed away by half its own grown extent plus the gap, so no two
  // icons ever overlap. When the pointer leaves, the same bindings that
  // draped the icons out fold them back, animated by the Behaviour on each
  // cell.

  property real pointerMain: 0
  property bool pointerInside: false
  readonly property bool fisheyeActive: magnify && pointerInside && !dragging && revealed

  // The lens never applies its targets directly. Every cell holds a current
  // scale and position that a 16 ms loop eases toward the computed targets,
  // and the peak anchor only hands off to a neighbour once the pointer has
  // cleared the boundary by a margin. This kills the two classic dock
  // jitters: the whole-row anchor jump when the most magnified cell hands
  // off, and the sawtooth re-easing of a Behaviour restarting on every
  // pointer move.

  property bool fishSmoothing: false   // the frame loop is winding down or up

  // Current (animated) per-cell scale and left edge. Lazily filled so a
  // freshly mounted cell reads the base layout before its first tick.
  property var fishScaleCur: []
  property var fishPosCur: []

  // Icon-row length at rest. A pure derivation of the item set so the card
  // always wraps exactly the icons on screen — no property writes, so it can
  // never go stale when the running section grows or shrinks. The lens
  // leaves it alone entirely; the border only resizes when items settle.
  readonly property int contentLength: baseContentLength

  function smoothScale(i) {
    return fishScaleCur && i < fishScaleCur.length && fishScaleCur[i] > 0 ? fishScaleCur[i] : 1.0
  }

  function smoothPos(i) {
    return fishPosCur && i < fishPosCur.length ? fishPosCur[i] : (cellPos[i] || 0)
  }

  // A cell's visual extent along the main axis at a given scale. Rules stay
  // their thin width regardless.
  function extentAt(i, scales) {
    var it = displayItems[i]
    if (Util.isPlainObject(it) && (it.spacer === true || it.__divider === true)) return ruleWidth
    return slot * (scales[i] || 1)
  }

  // Resting centre of each cell, in row coordinates.
  readonly property var baseCenters: {
    var list = displayItems
    var out = []
    var x = 0
    for (var i = 0; i < list.length; i++) {
      var w = cellSize(list[i])
      out.push(x + w / 2)
      x += w + gap
    }
    return out
  }

  // The instantaneous lens targets: every cell scales in place about its own
  // base centre, and nothing else moves. The kernel is a narrow quadratic
  // (peak span about one slot each way) so a hovered icon grows over its
  // neighbours — the classic fishbowl — while cells further out sit at
  // exact scale 1 and their base position.
  //
  // The border stays where it is for the whole hover: the row's resting
  // length is a dartboard already, and the lens reserves the card's pad
  // and the 240 px of label slack instead of asking the window to grow.
  // contentLength (hence windowMain and cardMain) is a pure derivation of
  // the item set, so the card always wraps exactly the icons on screen;
  // while the pointer is over the dock the card — and everything in it —
  // is frozen in place.
  function computedTargets() {
    var n = displayItems.length
    if (n === 0) return { scales: [], positions: [], length: 0 }

    var centers = baseCenters
    var T = slot * 1.9
    var boost = zoom
    var scales = new Array(n)
    var i
    for (i = 0; i < n; i++) {
      var it = displayItems[i]
      if (Util.isPlainObject(it) && (it.spacer === true || it.__divider === true)) { scales[i] = 1; continue }
      if (!centers[i]) { scales[i] = 1; continue }
      var d = Math.abs(root.pointerMain - centers[i])
      var p = 1.0 - d / T
      var s = 1
      if (p > 0) {
        s = 1 + boost * p * p   // quadratic fishbowl, macOS-style
        if (s < 1) s = 1
      }
      scales[i] = s
    }

    var pos = new Array(n)
    for (i = 0; i < n; i++) pos[i] = cellPos[i] || 0

    return { scales: scales, positions: pos, length: rowLength(pos, scales) }
  }

  function rowLength(pos, scales) {
    var n = pos.length
    var len = 0
    for (var i = 0; i < n; i++) {
      var right = pos[i] + extentAt(i, scales)
      if (right > len) len = right
    }
    return len
  }

  // One easing frame toward the computed targets — dash2dock's continuous
  // zoom damping. Once the pointer is gone and nothing moves, snap cleanly
  // onto the base layout and stop the loop.
  function fishStep() {
    var n = displayItems.length
    if (n === 0) { fishSmoothing = false; return }
    var targets = computedTargets()
    ensureFishState()

    var eased = 0.3
    var s = new Array(n)
    var p = new Array(n)
    var maxScaleDelta = 0
    var maxMove = 0
    for (var i = 0; i < n; i++) {
      var ts = targets.scales[i] || 1
      var cs = fishScaleCur[i]
      var ns = cs + (ts - cs) * eased
      if (ts >= 1 && ns < 1) ns = 1
      s[i] = ns
      var tp = targets.positions[i] !== undefined ? targets.positions[i] : (cellPos[i] || 0)
      var np = fishPosCur[i] + (tp - fishPosCur[i]) * eased
      p[i] = np
      var sc = Math.abs(ns - cs)
      var mv = Math.abs(np - fishPosCur[i])
      if (sc > maxScaleDelta) maxScaleDelta = sc
      if (mv > maxMove) maxMove = mv
    }
    fishScaleCur = s
    fishPosCur = p

    // The border never chases the lens: contentLength is a pure derivation of
    // the item set and the lens never touches it, so the window, the card
    // and the icons on it hold still — only each cell's scale moves.
    // The card's own `Behavior on width` glides the border when the item
    // set actually settles (a pin, an unpin, a running window closing).

    if (maxScaleDelta < 0.012 && !fisheyeActive) {
      for (var j = 0; j < n; j++) { s[j] = 1; p[j] = cellPos[j] || 0 }
      fishScaleCur = s
      fishPosCur = p
      fishSmoothing = false
    }
  }

  // Size the easing state to the current slots, keeping any in-flight value.
  function ensureFishState() {
    var n = displayItems.length
    if (fishScaleCur.length === n && fishPosCur.length === n) return
    var s = new Array(n)
    var p = new Array(n)
    for (var i = 0; i < n; i++) {
      s[i] = fishScaleCur && i < fishScaleCur.length && fishScaleCur[i] > 0 ? fishScaleCur[i] : 1
      p[i] = fishPosCur && i < fishPosCur.length ? fishPosCur[i] : (cellPos[i] || 0)
    }
    fishScaleCur = s
    fishPosCur = p
  }

  // Start chasing; called whenever the lens might need to move.
  function wakeFish() {
    if (!fishSmoothing) { ensureFishState(); fishSmoothing = true }
  }

  Timer {
    id: fishTick
    interval: 16
    repeat: true
    running: root.fishSmoothing
    onTriggered: root.fishStep()
  }

  onPointerInsideChanged: if (root.pointerInside) root.wakeFish()
  onFisheyeActiveChanged: if (root.fisheyeActive) root.wakeFish()
  onDisplayItemsChanged: root.wakeFish()

  // Resting content length (scale 1 everywhere).
  readonly property int baseContentLength: {
    var total = 0
    var list = displayItems
    for (var i = 0; i < list.length; i++) total += cellSize(list[i])
    return total + Math.max(0, list.length - 1) * gap
  }

  // -------------------------------------------------------------- sizing

  readonly property int slot: Style.space(num("iconSize", 44))
  readonly property int pad: Style.space(num0("padding", 8))
  readonly property int gap: Style.space(num0("spacing", 6))
  readonly property int ruleWidth: Math.max(1, Style.space(1))

  // Glyph ink is normalized to this fraction of the slot (see DockItem).
  readonly property real glyphInkTarget: fraction("glyphScale", 0.58) > 0 ? fraction("glyphScale", 0.58) : 0.58

  readonly property bool tiles: flag("tiles", false)
  readonly property int tileRadiusPx: Math.round(root.slot * fraction("tileRadius", 0.23))
  readonly property real tileInset: fraction("tileInset", 0.76)
  readonly property real tileOpacity: fraction("tileOpacity", 0.16)
  readonly property real backgroundOpacity: fraction("backgroundOpacity", 1.0)
  // When on, the taskbar's background opacity is kept equal to the dock's
  // `backgroundOpacity` setting (written as `bar.backgroundOpacity` in
  // shell.json). The background-opacity slider's `opacity` subcommand applies
  // both in one atomic write; there is deliberately no config-reactive
  // binding here, so writes never feed back into the reload loop.
  readonly property bool matchBarOpacity: flag("matchBarOpacity", false)
  // When on, the taskbar's corner shape tracks the dock's cornerShape /
  // cornerRadius (written as bar.cornerShape / bar.cornerRadius in
  // shell.json). The shape picker's `corner-shape` subcommand applies both in
  // one atomic write. Same user-driven only pattern as matchBarOpacity.
  readonly property bool matchBarCorners: flag("matchBarCorners", false)
  readonly property real iconOpacity: fraction("iconOpacity", 1.0)

  readonly property color glyphColor: root.config.glyphColor === "accent" ? Color.accent : Color.popups.text

  // Corner rounding for the card: "rounded" (theme rounding, or an explicit
  // cornerRadius px value), "square" (sharp, radius 0) or "pill" (fully
  // rounded ends).
  readonly property string cornerShape: {
    var s = String(config.cornerShape || "").toLowerCase()
    return (s === "square" || s === "pill") ? s : "rounded"
  }

  readonly property int cardRadius: {
    if (cornerShape === "square") return 0
    if (cornerShape === "pill") return Math.max(1, Math.round(cardCross / 2))
    // An explicit cornerRadius overrides the theme rounding. `radius` is a
    // dead key from the original seed config and is deliberately ignored —
    // its bogus `100` value would clamp every card into a pill, making
    // "rounded" indistinguishable from "pill".
    return root.config.cornerRadius !== undefined
      ? Style.space(num0("cornerRadius", 0))
      : Style.cornerRadius
  }

  // A cell's extent along the main axis.
  function cellSize(item) {
    return Util.isPlainObject(item) && (item.spacer === true || item.__divider === true)
      ? root.ruleWidth : root.slot
  }

  readonly property bool fullWidth: flag("fullWidth", false)
  readonly property int cardMain: Math.round(
    (vertical ? Border.top(dockBorder) : Border.left(dockBorder)) + pad + contentLength + pad
    + (vertical ? Border.bottom(dockBorder) : Border.right(dockBorder)))
  readonly property int cardCross: Math.round(
    (vertical ? Border.left(dockBorder) : Border.top(dockBorder)) + pad + slot + pad
    + (vertical ? Border.right(dockBorder) : Border.bottom(dockBorder)))
  readonly property int cardWidth: vertical ? cardCross : cardMain
  readonly property int cardHeight: vertical ? cardMain : cardCross

  // The label pill sits in a band on the inward side of the card. Grown
  // fisheye icons lift into that same band, so the cross dimension grows by
  // the maximum lift too — the largest scaled icon plus its rise.
  readonly property int zoomOverflow: Math.round(slot * zoom * (0.5 + zoomRaise)) + Style.space(4)
  readonly property int labelHeight: Math.round(Style.font.bodySmall + Style.spacing.sm * 2 + Style.space(2))
  readonly property int labelBand: !labels ? zoomOverflow
    : vertical ? Style.space(220) + Style.spacing.sm + zoomOverflow
               : labelHeight + Style.spacing.sm + zoomOverflow

  // Gap between card and screen edge. The window still reaches the edge —
  // the strip between card and edge is live hover area, so the reveal never
  // drops from a stray pixel. Left unset it tracks the theme's edge gap.
  readonly property int edgeGap: root.config.edgeGap !== undefined
    ? Style.space(num0("edgeGap", 0))
    : Math.max(Style.gapsOut, Style.space(4))

  // Window extents. Cross: edge strip + card + label band. Main: the card
  // plus slack for a label centred on an end icon to spill into.
  //
  // While the settings popup is open, both axes keep the slack they would
  // need at the slider's largest icon size. The card stays pinned to the
  // edge/alignment (bottom, centred), so the extras are invisible click-
  // through strips, but the window itself never re-sizes while a control is
  // live. That matters: an xdg-popup child of a resizing window is re-
  // anchored by the compositor over several frames, and the border of the
  // popup is what shows that churn as a ghost. With the window frozen the
  // popup map is never disturbed.
  readonly property int iconSizeMax: 96
  function windowAxesAt(sv) {
    var total = 0
    var list = displayItems
    var n = list.length
    for (var i = 0; i < n; i++) {
      var it = list[i]
      total += Util.isPlainObject(it) && (it.spacer === true || it.__divider === true) ? ruleWidth : sv
    }
    total += Math.max(0, n - 1) * gap
    var cardMain = Border.left(dockBorder) + pad + total + pad + Border.right(dockBorder)
    var cardCross = Border.top(dockBorder) + pad + sv + pad + Border.bottom(dockBorder)
    var zoomOverflow = Math.round(sv * zoom * (0.5 + zoomRaise)) + Style.space(4)
    var labelBand = !labels ? zoomOverflow
      : vertical ? Style.space(220) + Style.spacing.sm + zoomOverflow
                 : labelHeight + Style.spacing.sm + zoomOverflow
    return {
      main: Math.round(cardMain + (labels && !vertical ? Style.space(240) : 0)),
      cross: Math.round(labelBand + cardCross + edgeGap)
    }
  }
  readonly property int reserveMain: settingsOpen ? Math.max(0, windowAxesAt(Style.space(iconSizeMax)).main - windowAxesAt(root.slot).main) : 0
  readonly property int reserveCross: settingsOpen ? Math.max(0, windowAxesAt(Style.space(iconSizeMax)).cross - windowAxesAt(root.slot).cross) : 0
  readonly property int windowCross: labelBand + cardCross + edgeGap + glowCrossExtra
  // Glow room rides along on the main axis too (whichever flanks need it).
  readonly property int windowMain: cardMain + (labels && !vertical ? Style.space(240) : 0) + glowMainExtra
  readonly property int windowWidth: vertical ? windowCross + reserveCross : windowMain + reserveMain
  readonly property int windowHeight: vertical ? windowMain + reserveMain : windowCross + reserveCross

  // Where along the cross axis, in window coordinates, the card's edge
  // strip and the card itself begin. Pillars against the first edge sit at
  // the top/left as usual; pillars against the last edge are pinned to the
  // bottom/right of the *window buffer* (their docked edge). The buffer's
  // cross extent includes whatever is reserved while the settings popup is
  // open — windowCross alone is the un-reserved figure and would leave the
  // card floating panel-height above the docked edge until the popup closes.
  readonly property int crossAxisLen: vertical ? windowWidth : windowHeight
  readonly property int cardCrossLen: cardCross
  readonly property int hitCross: edgeFirst ? 0 : Math.max(0, crossAxisLen - edgeGap - cardCrossLen)
  readonly property int cardCrossPos: edgeFirst ? edgeGap : Math.max(0, crossAxisLen - edgeGap - cardCrossLen)
  // The inward face of the card: where popups hang off.
  readonly property int cardInnerFace: edgeFirst ? edgeGap + cardCross : labelBand

  // Popups hang off the card's inward face, centred on the icon along the
  // edge. Gravity is the direction the popup grows in from its 1×1 anchor.
  readonly property int popupGravity: edge === "bottom" ? (Edges.Top | Edges.Right)
                                    : edge === "top"    ? (Edges.Bottom | Edges.Right)
                                    : edge === "left"   ? (Edges.Right | Edges.Bottom)
                                    :                     (Edges.Left | Edges.Bottom)

  function popupAnchorPoint(target, window, popupW, popupH, clearMax) {
    var pos = window.contentItem.mapFromItem(target, 0, 0)
    var gapIn = Style.spacing.sm
    var across
    if (clearMax) {
      // The settings popup opens against the card's *maximum* inward face:
      // while it is open the window buffer is frozen at the slider's biggest
      // icon size, so the card can grow that far. Anchor the popup clear of
      // that, otherwise dragging the slider to the top would slide the grown
      // card up under the popup's bottom edge. The menu, which hugs the card
      // at its current size, keeps the plain branch.
      var maxCardAcross = root.maxCardThickness()
      var unReservedLen = windowCross
      across = edgeFirst ? maxCardAcross + edgeGap + gapIn
                         : unReservedLen - edgeGap - maxCardAcross - gapIn
    } else {
      across = edgeFirst ? cardInnerFace + gapIn : cardInnerFace - gapIn
    }
    if (vertical) {
      var y = vertical && clearMax
        ? Math.round(root.windowHeight / 2 - popupH / 2)
        : Math.round(pos.y + target.height / 2 - popupH / 2)
      y = Math.max(0, Math.min(y, window.height - popupH))
      return { x: across, y: y }
    }
    var x = clearMax
      ? Math.round(root.windowWidth / 2 - popupW / 2)
      : Math.round(pos.x + target.width / 2 - popupW / 2)
    x = Math.max(0, Math.min(x, window.width - popupW))
    return { x: x, y: across }
  }

  // Main-axis offset of a card of the given length inside a window of the
  // given length, per `align`.
  function cardMainOffset(winLen, cardLen) {
    if (align === "start") return 0
    if (align === "end") return Math.max(0, winLen - cardLen)
    return Math.round((winLen - cardLen) / 2)
  }

  // ---------------------------------------------------------- reveal state

  // Hover is tallied rather than assigned: moving between the hotspot and
  // the dock can deliver the enter before the leave, and a plain assignment
  // would strand the dock closed.
  property int hotspotHovers: 0
  property int dockHovers: 0
  property string activeScreen: ""
  property bool revealed: false

  property string hoveredLabel: ""
  property int hoveredIndex: -1
  // Main-axis centre of the hovered icon, in window coordinates.
  property real hoveredCenter: 0

  readonly property bool wantOpen: !autohide
    || (active && !dodgeBlocked && (hotspotHovers > 0 || dockHovers > 0))

  // True when the named output's active workspace holds no windows.
  function screenEmpty(name) {
    var monitors = Hyprland.monitors.values || []
    for (var i = 0; i < monitors.length; i++) {
      if (String(monitors[i].name || "") !== name) continue
      var ws = monitors[i].activeWorkspace
      if (!ws || !ws.toplevels) return false
      return (ws.toplevels.values || []).length === 0
    }
    return false
  }

  // Which monitor the dock belongs to right now. Hovering an edge names it
  // outright; a summon over IPC has no pointer to go on, so it falls back to
  // the focused monitor.
  readonly property string targetScreen: {
    if (root.activeScreen !== "") return root.activeScreen
    var focused = Hyprland.focusedMonitor
    return focused ? String(focused.name || "") : ""
  }

  // Held open by IPC rather than by the pointer.
  property bool held: false

  onWantOpenChanged: {
    if (wantOpen) {
      if (!root.popupOpen) held = false
      hideTimer.stop()
      revealTimer.restart()
    } else {
      revealTimer.stop()
      hideTimer.restart()
    }
  }

  onRevealedChanged: {
    if (revealed) {
      evaluateConditions()
    } else {
      hoveredLabel = ""
      pointerInside = false
      contextMenu.close()
      settingsWindow.close()
    }
  }

  Timer {
    id: revealTimer
    interval: root.revealDelay
    onTriggered: root.revealed = true
  }

  Timer {
    id: hideTimer
    interval: root.hideDelay
    onTriggered: if (!root.held) root.revealed = false
  }

  // --------------------------------------------------------- intelli-hide
  //
  // dash2dock's "dodge": keep the dock out of the way of windows. While
  // enabled, the dock stays hidden if any window on its workspace overlays
  // the card's area on screen (fullscreen windows always count). The check
  // runs on a short poll — geometry arrives over Hyprland IPC, which has no
  // reactive channel — and only bites while something is hovering the
  // reveal, so it never burns cycles when the dock is up and idle.

  // The region of the target output that the card would cover when
  // revealed: an edge band as thick as the card and its edge gap. Windows
  // are checked against the *whole* band, not the card's exact main-axis
  // span — a maximized window in Hyprland always covers the edge, and
  // checking the precise card rect bought nothing but fiddly surface math.
  // All coordinates are global compositor-layout units, the space Hyprland
  // reports monitor and window geometry in.
  function edgeStripRect(name) {
    var monitors = Hyprland.monitors.values || []
    var m = null
    for (var i = 0; i < monitors.length; i++) {
      if (String(monitors[i].name || "") === name) { m = monitors[i]; break }
    }
    if (!m) return null
    var thick = root.edgeGap + root.cardCross + 2
    if (root.edge === "bottom") return { x: m.x, y: m.y + m.height - thick, width: m.width, height: thick }
    if (root.edge === "top")    return { x: m.x, y: m.y, width: m.width, height: thick }
    if (root.edge === "right")  return { x: m.x + m.width - thick, y: m.y, width: thick, height: m.height }
    return { x: m.x, y: m.y, width: thick, height: m.height }
  }

  // The dock window's on-screen rect (global compositor-layout units), as
  // the layer would place it for the current edge/align/fullWidth and window
  // size. Hyprland reports window layer geometry in these units; QML exposes
  // the window's width/height but not x/y, so the anchor math mirrors the
  // layer-shell rules instead of reading them.
  function windowScreenRect(name) {
    var monitors = Hyprland.monitors.values || []
    var m = null
    for (var i = 0; i < monitors.length; i++) {
      if (String(monitors[i].name || "") === name) { m = monitors[i]; break }
    }
    if (!m) return null
    var horizontal = root.edge === "bottom" || root.edge === "top"
    var mainLen = horizontal ? m.width : m.height
    var crossLen = horizontal ? m.height : m.width
    var winMainLen = horizontal ? root.windowWidth : root.windowHeight
    var winCrossLen = horizontal ? root.windowHeight : root.windowWidth
    if (root.fullWidth) winMainLen = mainLen
    var mainPos = root.align === "start" ? 0
      : root.align === "end" ? mainLen - winMainLen
      : Math.round((mainLen - winMainLen) / 2)
    if (root.edge === "bottom") return { x: m.x + mainPos, y: m.y + crossLen - winCrossLen }
    if (root.edge === "top")    return { x: m.x + mainPos, y: m.y }
    if (root.edge === "right")  return { x: m.x + m.width - winCrossLen, y: m.y + mainPos }
    return                           { x: m.x, y: m.y + mainPos }
  }

  // Ground-truth monitor rect (global compositor-layout units) for a named
  // output, for positioning the settings popup on screen.
  function monitorRect(name) {
    var monitors = Hyprland.monitors.values || []
    for (var i = 0; i < monitors.length; i++) {
      if (String(monitors[i].name || "") === name) return monitors[i]
    }
    return null
  }

  // The card's thickness at a given icon slot (i.e. its extent on the cross
  // axis, the direction it reaches in from the screen edge). The slider can
  // grow the card to iconSizeMax, so the settings popup keeps clear of that.
  function maxCardThickness(sv) {
    var s = sv !== undefined ? sv : Style.space(iconSizeMax)
    return (vertical ? Border.left(dockBorder) + Border.right(dockBorder)
                     : Border.top(dockBorder) + Border.bottom(dockBorder))
         + 2 * pad + s
  }

  property bool dodgeBlocked: false

  function rectsOverlap(r1, r2) {
    return !(r2.x >= r1.x + r1.width || r2.x + r2.width <= r1.x
          || r2.y >= r1.y + r1.height || r2.y + r2.height <= r1.y)
  }

  function dodgeBlockedNow() {
    if (!root.dodge || !autohide) return false
    var rect = root.edgeStripRect(root.targetScreen)
    if (!rect) return false
    var monName = root.targetScreen
    if (!monName) return false
    var monitors = Hyprland.monitors.values || []
    var screen = null
    for (var i = 0; i < monitors.length; i++)
      if (String(monitors[i].name || "") === monName) { screen = monitors[i]; break }
    if (!screen || !screen.activeWorkspace) return false
    var wsId = screen.activeWorkspace.id
    var tops = Hyprland.toplevels.values || []
    for (var j = 0; j < tops.length; j++) {
      var t = tops[j]
      if (t.workspace && wsId !== undefined && t.workspace.id !== wsId) continue
      var ipc = t.lastIpcObject || {}
      if (ipc.fullscreen === true) return true
      var x = Number(ipc.x), y = Number(ipc.y), w = Number(ipc.width), h = Number(ipc.height)
      if (w > 0 && h > 0 && isFinite(x) && isFinite(y)
          && root.rectsOverlap({ x: x, y: y, width: w, height: h }, rect)) return true
    }
    return false
  }

  Timer {
    id: dodgeTimer
    interval: 150
    repeat: true
    running: root.dodge && autohide
    triggeredOnStart: true
    onTriggered: root.dodgeBlocked = root.dodgeBlockedNow()
  }

  onDodgeBlockedChanged: {
    if (dodgeBlocked && revealed && !held && !popupOpen) {
      revealed = false
      hoveredLabel = ""
      contextMenu.close()
    }
  }

  function open() {
    revealTimer.stop()
    hideTimer.stop()
    held = true
    revealed = true
  }

  function close() {
    revealTimer.stop()
    hideTimer.stop()
    held = false
    revealed = false
  }

  // ------------------------------------------------------------ app helpers

  function desktopEntry(item) {
    if (!Util.isPlainObject(item)) return null
    var want = String(item.desktop || "").replace(/\.desktop$/, "")
    if (!want) return null
    var values = (DesktopEntries.applications && DesktopEntries.applications.values) || []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (entry && String(entry.id || "").replace(/\.desktop$/, "") === want) return entry
    }
    return null
  }

  function appLabel(item, entry) {
    if (!Util.isPlainObject(item)) return ""
    if (item.label) return String(item.label)
    if (entry && entry.name) return String(entry.name)
    if (item.desktop) return String(item.desktop)
    if (item.showApps === true) return "Apps"
    if (item.trash === true) return "Trash"
    return ""
  }

  // What the hover label shows: an explicit `label` always wins, then the
  // entry's name.
  function itemLabel(item, entry) {
    if (!Util.isPlainObject(item)) return ""
    if (item.label) return String(item.label)
    return root.appLabel(item, entry)
  }

  function itemIcon(item, entry) {
    var name = Util.isPlainObject(item) && item.icon
      ? String(item.icon)
      : (entry && entry.icon ? String(entry.icon) : "")
    var library = root.shell ? root.shell.appLibrary : null
    if (library) return library.iconSource(name)
    if (name.charAt(0) === "/") return Util.fileUrl(name)
    return Quickshell.iconPath(name || "application-x-executable", true)
  }

  // dash2dock activate(): a running and focused app toggles to minimize; a
  // running but unfocused one focuses its most-recently-used window; not
  // running launches.
  function activate(item, entry) {
    if (!Util.isPlainObject(item)) return

    if (item.showApps === true) { Util.execDetached("omarchy-menu"); return }
    if (item.trash === true) { Util.execDetached("xdg-open trash:///"); return }

    var wins = root.windowsFor(item)
    if (wins.length > 0) {
      var act = ToplevelManager.activeToplevel
      if (act && wins.indexOf(act) >= 0) {
        act.setMinimized(!act.minimized)
        return
      }
      wins[0].activate()
      return
    }
    launchNew(item, entry)
  }

  function launchNew(item, entry) {
    if (!Util.isPlainObject(item)) return
    if (item.showApps === true) { Util.execDetached("omarchy-menu"); return }
    if (item.trash === true) { Util.execDetached("xdg-open trash:///"); return }
    if (item.exec) { Util.execDetached(String(item.exec)); return }
    if (entry && root.shell && root.shell.appLibrary) {
      root.shell.appLibrary.launch(entry.id, entry.name)
      return
    }
    if (item.desktop) {
      var id = String(item.desktop).replace(/\.desktop$/, "")
      Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
    }
  }

  // The context menu's New Window. An entry that ships a new-window desktop
  // action runs that action's command; anything else launches plainly.
  function launchNewWindow(item, entry) {
    var action = root.newWindowAction(entry)
    if (!action) {
      launchNew(item, entry)
      return
    }
    runDesktopAction(entry, action)
  }

  function runDesktopAction(entry, action) {
    if (!action || !action.command || action.command.length < 1) return
    var argv = ["uwsm-app", "--"]
    for (var i = 0; i < action.command.length; i++) argv.push(String(action.command[i]))
    var spec = { command: argv }
    if (entry && entry.workingDirectory) spec.workingDirectory = String(entry.workingDirectory)
    Quickshell.execDetached(spec)
  }

  function isNewWindowAction(action) {
    var id = String(action && action.id || "").toLowerCase().replace(/_/g, "-")
    return id === "new-window" || id === "newwindow"
  }

  function desktopActions(entry) {
    if (!entry || entry.runInTerminal || !entry.actions) return []
    var out = []
    var list = entry.actions
    for (var i = 0; i < list.length; i++) {
      var a = list[i]
      if (!a || !a.command || a.command.length < 1) continue
      out.push(a)
    }
    return out
  }

  function newWindowAction(entry) {
    var list = root.desktopActions(entry)
    for (var i = 0; i < list.length; i++)
      if (root.isNewWindowAction(list[i])) return list[i]
    return null
  }

  // Every action except the new-window one, for the menu's app section.
  function menuActions(entry) {
    return root.desktopActions(entry).filter(function (a) { return !root.isNewWindowAction(a) })
  }

  // Whether any of the item's windows is the current active toplevel.
  function hasActiveWindow(item) {
    var wins = root.windowsFor(item)
    if (wins.length === 0) return false
    var act = ToplevelManager.activeToplevel
    if (!act) return false
    for (var i = 0; i < wins.length; i++) if (wins[i] === act) return true
    return false
  }

  // Scroll-to-cycle windows. steps are whole wheel steps accumulated by the
  // cell; the next window in MRU order activates, and the label flashes its
  // title like a mini window-switcher.
  function cycleWindows(cell, steps) {
    if (!cell || cell.isRule || steps === 0) return
    var wins = cell.wins
    if (wins.length === 0) {
      if (steps > 0) activate(cell.modelData, cell.entry)
      return
    }
    var act = ToplevelManager.activeToplevel
    var idx = wins.indexOf(act)
    var target
    if (idx >= 0) {
      target = wins[(idx + steps + wins.length) % wins.length]
    } else {
      target = steps > 0 ? wins[0] : wins[wins.length - 1]
    }
    target.activate()
    hoveredLabel = String(target.title || (cell && cell.label) || "")
    labelFlash.restart()
  }

  Timer {
    id: labelFlash
    interval: 900
    onTriggered: if (root.hoveredLabel !== "") root.hoveredLabel = ""
  }// ---------------------------------------------------------- reveal zone
  //
  // A sliver along the dock's edge, sized to the dock by default so the
  // reveal zone is exactly where the dock will appear. Lives on the Top
  // layer; the dock itself is on Overlay, so where the two overlap the dock
  // wins the pointer and the hotspot never steals a click.
  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      id: hotspotWindow
      required property var modelData

      screen: modelData
      visible: root.active
      color: "transparent"
      // Reserve nothing, but respect what others reserve: the bar's
      // exclusive zone pushes the zone (and the dock) off the bar, so a
      // top or vertical dock lands beside it rather than under it.
      exclusionMode: ExclusionMode.Normal
      exclusiveZone: 0
      WlrLayershell.namespace: "omarchy-animated-dock-hotspot"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      // A full-length dock gets a full-length trigger zone regardless of
      // the hotspot setting — a centred sliver under a monitor-wide card
      // would be a guessing game. Otherwise the zone follows the card's
      // alignment: anchored to the same side, offset by the same edge gap.
      readonly property bool span: root.hotspotFullWidth || root.fullWidth
      anchors {
        bottom: root.edge === "bottom" || (root.vertical && (span || root.align === "end"))
        top:    root.edge === "top"    || (root.vertical && (span || root.align === "start"))
        left:   root.edge === "left"   || (!root.vertical && (span || root.align === "start"))
        right:  root.edge === "right"  || (!root.vertical && (span || root.align === "end"))
      }
      margins {
        left:   (!root.vertical && !span && root.align === "start") ? root.edgeGap : 0
        right:  (!root.vertical && !span && root.align === "end")   ? root.edgeGap : 0
        top:    (root.vertical  && !span && root.align === "start") ? root.edgeGap : 0
        bottom: (root.vertical  && !span && root.align === "end")   ? root.edgeGap : 0
      }

      implicitWidth:  root.vertical ? root.hotspotHeight : (span ? 0 : root.cardMain)
      implicitHeight: root.vertical ? (span ? 0 : root.cardMain) : root.hotspotHeight
      // Bind the size explicitly: layer-shell surfaces pick up their size at
      // map time from implicit sizes, but don't re-read later implicit
      // changes. An explicit width/height tracks every item-set settle, so
      // the trigger zone hugs the card as it grows or shrinks. `span` keeps
      // the full-length pixel unpinned — the two side anchors already make
      // it monitor-wide there.
      width:  root.vertical ? root.hotspotHeight : (span ? undefined : root.cardMain)
      height: root.vertical ? (span ? undefined : root.cardMain) : root.hotspotHeight

      // The handler needs an Item to attach to; a pointer handler parented
      // straight to the window never receives anything.
      Item {
        anchors.fill: parent

        HoverHandler {
          id: hotspotHover
          property bool counted: false

          onHoveredChanged: {
            if (hovered === counted) return
            counted = hovered
            root.hotspotHovers += hovered ? 1 : -1
            if (hovered) root.activeScreen = String(hotspotWindow.modelData.name || "")
          }

          // Unplugging a monitor destroys its hotspot without a leave event,
          // which would strand the tally and hold the dock open for good.
          Component.onDestruction: if (counted) root.hotspotHovers -= 1
        }
      }
    }
  }

  // ----------------------------------------------------------------- dock

  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      id: dockWindow
      required property var modelData

      readonly property string screenName: String(modelData.name || "")

      // Asks about the workspace on *this* output, not the focused one. The
      // pin only applies to the monitor being used: with several monitors an
      // idle secondary output still auto-hides under its own empty workspace,
      // while the empty workspace you actually engage keeps its launcher up.
      readonly property bool pinnedOpen: root.showWhenEmpty
        && root.screenEmpty(screenName)
        && (root.targetScreen === "" || root.targetScreen === screenName)

      // With several monitors the dock appears only on the one being asked
      // for; the empty-target case means we could not tell, so show it here
      // rather than nowhere.
      readonly property bool shown: pinnedOpen
        || (root.revealed && (root.targetScreen === "" || root.targetScreen === screenName))

      screen: modelData
      visible: root.active
      color: "transparent"
      exclusionMode: ExclusionMode.Normal
      exclusiveZone: 0
      WlrLayershell.namespace: "omarchy-animated-dock"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      // Anchored to its edge. Along the edge, layer-shell centres a surface
      // on any axis it is not anchored to — the `center` alignment for
      // free; start/end anchor that side and offset by the edge gap so the
      // card sits as far from the corner as it does from the edge.
      // Full-length anchors both sides instead, and the card takes the
      // monitor's length minus the edge gap on either flank.
      readonly property bool anchorStart: root.fullWidth || root.align === "start"
      readonly property bool anchorEnd: root.fullWidth || root.align === "end"
      anchors.bottom: root.edge === "bottom" || (root.vertical && anchorEnd)
      anchors.top:    root.edge === "top"    || (root.vertical && anchorStart)
      anchors.left:   root.edge === "left"   || (!root.vertical && anchorStart)
      anchors.right:  root.edge === "right"  || (!root.vertical && anchorEnd)

      // Card length along the edge, and its offset within the window.
      readonly property int winMain: root.vertical ? dockWindow.height : dockWindow.width
      readonly property int cardLen: root.fullWidth
        ? Math.max(root.cardMain, winMain - root.edgeGap * 2)
        : root.cardMain
      readonly property int cardOffset: root.fullWidth
        ? Math.round((winMain - cardLen) / 2)
        : root.cardMainOffset(winMain, cardLen)

      // On-screen card size for this window. The cross size is fixed by the
      // slot; the card reflows along the edge as the fisheye lens slides.
      readonly property int cardW: root.vertical ? root.cardCross : cardLen
      readonly property int cardH: root.vertical ? cardLen : root.cardCross

      implicitWidth: root.windowWidth
      implicitHeight: root.windowHeight
      // Same story as the hotspot: bind the size explicitly so the window
      // follows every contentLength change instead of freezing at the size
      // it had when it first mapped.
      width: root.windowWidth
      height: root.windowHeight

      // Input is confined to the card and the strip between it and the
      // edge. The label band and the empty length either side of the card
      // stay click-through. Bound to explicit bounds rather than `item:` —
      // an item-shaped region never picked up hitArea's geometry.
      mask: Region {
        x: hitArea.x
        y: hitArea.y
        width: hitArea.width
        height: hitArea.height
      }

      // 0 = docked, 1 = parked off-screen.
      property real slide: dockWindow.shown ? 0 : 1
      Behavior on slide {
        NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
      }

      // Parked = pushed out past its own edge. The start/end margins keep
      // the card an edge gap away from the corner it's aligned to.
      readonly property int park: -Math.round(dockWindow.slide * (root.windowCross + Style.space(6)))
      readonly property int sideGap: (root.fullWidth || root.align === "center") ? 0 : root.edgeGap
      margins {
        bottom: root.edge === "bottom" ? park : (root.vertical  && root.align === "end"   ? sideGap : 0)
        top:    root.edge === "top"    ? park : (root.vertical  && root.align === "start" ? sideGap : 0)
        left:   root.edge === "left"   ? park : (!root.vertical && root.align === "start" ? sideGap : 0)
        right:  root.edge === "right"  ? park : (!root.vertical && root.align === "end"   ? sideGap : 0)
      }

      // The card and the strip of edge gap outside it are one subtree, so
      // the whole reveal region hovers as a unit. The dock can reveal from
      // the strip alone — the fisheye only engages over the card itself,
      // and the strip is where a wrist prods the screen edge.
      Item {
        id: hitArea
        x: root.vertical ? root.hitCross : dockWindow.cardOffset
        y: root.vertical ? dockWindow.cardOffset : root.hitCross
        width:  root.vertical ? root.cardCross + root.edgeGap : dockWindow.cardW
        height: root.vertical ? dockWindow.cardH : root.cardCross + root.edgeGap

        HoverHandler {
          id: dockHover
          property bool counted: false

          onHoveredChanged: {
            if (hovered === counted) return
            counted = hovered
            root.dockHovers += hovered ? 1 : -1
            root.pointerInside = hovered
            if (hovered) root.activeScreen = dockWindow.screenName
          }

          // The lens's input: every move inside the strip reports the
          // pointer's main-axis position in row coordinates. Rows are laid
          // out identically in every window, so the root's single
          // pointerMain is well-defined whichever window is showing.
          onPointChanged: {
            var p = hitArea.mapToItem(row, point.position.x, point.position.y)
            root.pointerMain = root.vertical ? p.y : p.x
          }

          Component.onDestruction: if (counted) root.dockHovers -= 1
        }

        // Border glow. Plain translucent ring strokes stacked one pixel beyond
        // the card's border, each fainter than the last — no effect passes,
        // no texture sampling. Every stroke is a Rectangle bound to the
        // same card size and animated with the same duration, so the glow
        // is always identical to the dock border: same width, height,
        // position and radius, tracking icon add/remove reflows in lockstep
        // instead of lagging behind them. The first stroke is centred on
        // the border line itself, so the light reads as coming FROM the
        // outline rather than sitting detached behind the card.
        Item {
          id: glowLayers
          visible: root.glowEnabled && dockWindow.shown
          z: -1
          x: (root.vertical && root.edgeFirst) ? root.edgeGap : 0
          y: (!root.vertical && root.edgeFirst) ? root.edgeGap : 0
          width: dockWindow.cardW
          height: dockWindow.cardH
          Behavior on width {
            NumberAnimation { duration: root.settingsOpen ? 0 : root.animMs; easing.type: Easing.OutCubic }
          }
          Behavior on height {
            NumberAnimation { duration: root.settingsOpen ? 0 : root.animMs; easing.type: Easing.OutCubic }
          }
          opacity: card.opacity
          Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
          }

          // One 2px stroke per pixel-envelope step. `step` moves the ring
          // edge outward; the stroke-half inside each edge is what hugs the
          // border: step 0 is centred exactly on the border line, and the
          // envelope grows 1px a layer to a 4px fade. `glowFocus` "bottom"
          // nudges the whole stack one pixel toward the docked edge.
          Repeater {
            model: [0, 1, 2, 3]

            Rectangle {
              required property int index
              readonly property int step: modelData
              x: -1 - step + root.glowShiftX
              y: -1 - step + root.glowShiftY
              width: parent.width + (2 + step * 2)
              height: parent.height + (2 + step * 2)
              radius: Math.max(0, root.cardRadius + 1 + step)
              color: "transparent"
              border.width: 2
              border.color: Util.alpha(root.glowColor,
                root.glowStrength * [0.50, 0.32, 0.18, 0.10][step])
            }
          }
        }

        BorderSurface {
          id: card
          // Inside the hit area the card sits away from the edge strip:
          // after it on left/top, before it on right/bottom.
          x: (root.vertical && root.edgeFirst) ? root.edgeGap : 0
          y: (!root.vertical && root.edgeFirst) ? root.edgeGap : 0
          width: dockWindow.cardW
          height: dockWindow.cardH
          // The card length animates with the lens so the grown row is
          // always wrapped, never clipped. With the settings popup open the
          // card instead snaps to the new size: an animated edge sweeping
          // under the popup's translucent margin reads as ghosting next to
          // its border.
          Behavior on width {
            NumberAnimation { duration: root.settingsOpen ? 0 : root.animMs; easing.type: Easing.OutCubic }
          }
          Behavior on height {
            NumberAnimation { duration: root.settingsOpen ? 0 : root.animMs; easing.type: Easing.OutCubic }
          }
          radius: root.cardRadius
          // The popup surface, not the raw palette background: a theme that
          // tints its popups should tint the dock the same way.
          color: Util.alpha(Color.popups.background, root.backgroundOpacity)
          borderSpec: root.dockBorder

          opacity: dockWindow.shown ? 1 : 0
          Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
          }

          // The dock's own background dismisses the menu (the dock sits
          // inside the menu's focus grab, so the grab won't dismiss for us
          // here). Passive gesture policy, so it coexists with the per-icon
          // tap handlers rather than stealing their presses.
          TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: root.closeMenu()
          }

          // Not a Row/Column: cells place themselves from root.cellPos /
          // smoothPos so a drag can hold a gap open while the rest of the
          // layout stays put behind it.
          Item {
            id: row
            anchors.centerIn: parent
            width:  root.vertical ? root.slot : root.contentLength
            height: root.vertical ? root.contentLength : root.slot

            Repeater {
              model: root.displayItems

              // The slot itself lives in DockItem.qml; Repeater fills
              // modelData/index, the root comes along explicitly.
              delegate: DockItem { dock: root }
            }
          }
        }
      }

      BorderSurface {
        id: tip
        visible: root.labels && root.flag("tooltips", true) && dockWindow.shown && root.hoveredLabel !== "" && !root.dragging
        height: root.labelHeight
        width: Math.round(tipText.implicitWidth + Style.spacing.xxl * 2)
        // Centred on the hovered icon along the edge, clamped so a label
        // near either end of the dock stays inside the window; on the cross
        // axis it hangs off the card's inward face, in the label band.
        readonly property int along: Math.round(Math.max(Style.spacing.sm,
          Math.min((root.vertical ? dockWindow.height - height : dockWindow.width - width) - Style.spacing.sm,
                   root.hoveredCenter - (root.vertical ? height : width) / 2)))
        readonly property int across: root.edgeFirst
          ? root.cardInnerFace + Style.spacing.sm
          : root.labelBand - Style.spacing.sm - (root.vertical ? width : height)
        x: root.vertical ? across : along
        y: root.vertical ? along : across
        radius: Math.min(root.cardRadius, Math.round(root.labelHeight / 2))
        color: Util.alpha(Color.background, 0.97)
        borderSpec: root.tipBorder

        Text {
          id: tipText
          anchors.centerIn: parent
          text: root.hoveredLabel

          // The window title (`hoveredLabel`) is remote/untrusted content —
          // e.g. a browser tab name. Force plain text so title markup can
          // never be interpreted as rich text (no image/resource loading
          // from an injected <img src=…>).
          textFormat: Text.PlainText

          color: Color.tooltip.text
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  // ------------------------------------------------------------------ ipc
  //
  // Lets a keybinding summon the dock without reaching for the edge, and
  // makes the reveal state inspectable when something misbehaves.
  //   omarchy-shell animated.dock toggle
  IpcHandler {
    target: "animated.dock"

    function show(): string { root.open(); return "ok" }
    function hide(): string { root.close(); return "ok" }
    function toggle(): string { if (root.revealed) root.close(); else root.open(); return "ok" }

    // Fire a pinned slot without the pointer, so a keybinding can reach one.
    // Slots are 1-based and count spacers, matching the items[] order.
    function launch(slot: string): string {
      var i = Math.round(Number(slot)) - 1
      if (!(i >= 0 && i < root.items.length)) return "no such slot"
      var item = root.items[i]
      root.activate(item, root.desktopEntry(item))
      return "ok"
    }

    // Open the context menu on a display slot (1-based, counting rules),
    // so a test or keybinding can reach it without the pointer.
    function menu(slot: string): string {
      var i = Math.round(Number(slot)) - 1
      if (!(i >= 0 && i < root.displayItems.length)) return "no such slot"
      var cell = root.cellAt(i)
      if (!cell) return "no cell"
      root.open()
      root.openMenu(cell)
      return "ok"
    }

    function menuClose(): string { root.closeMenu(); return "ok" }

    // Tap a row of the open menu by 0-based index (separators count), so a
    // test can drive the picker without the pointer. `state` lists labels.
    function menuRun(row: string): string {
      if (!root.menuOpen) return "menu closed"
      var i = Math.round(Number(row))
      var rows = contextMenu.rows
      if (!(i >= 0 && i < rows.length)) return "no such row"
      if (rows[i].kind === "sep") return "separator"
      contextMenu.run(rows[i])
      return "ok"
    }

    // Inspect the reveal machinery.
    function state(): string {
      return JSON.stringify({
        revealed: root.revealed,
        held: root.held,
        dodgeBlocked: root.dodgeBlocked,
        targetScreen: root.targetScreen,
        activeScreen: root.activeScreen,
        hovering: root.hotspotHovers > 0 || root.dockHovers > 0,
        pointerInside: root.pointerInside,
        items: root.displayItems.length,
        label: root.hoveredLabel
      })
    }

    // Lay out the numbers so a length mismatch is visible at a glance: what
    // the card claims to wrap vs what the cells actually fill, and where
    // each edge of the card lands on the output.
    function geometry(): string {
      var winLen = root.vertical ? root.windowHeight : root.windowWidth
      var cardLen = root.vertical ? root.cardH : root.cardW
      var shown = []
      for (var i = 0; i < root.displayItems.length; i++) {
        var cell = root.cellAt(i)
        shown.push(cell ? {
          i: i,
          index: cell.index,
          x: Math.round(cell.x),
          w: Math.round(cell.width)
        } : null)
      }
      return JSON.stringify({
        items: root.displayItems.length,
        contentLength: root.contentLength,
        baseContentLength: root.baseContentLength,
        cardMain: root.cardMain,
        cardLen: cardLen,
        winLen: winLen,
        winMain: root.windowMain,
        cardOffset: root.align === "center" && !root.fullWidth
          ? Math.round((winLen - cardLen) / 2) : Math.max(0, winLen - cardLen),
        pad: root.pad,
        gap: root.gap,
        cells: shown
      })
    }
  }

  Component.onCompleted: {
    evaluateConditions()
    if (!root.autohide) {
      held = true
      revealed = true
    }
  }
}