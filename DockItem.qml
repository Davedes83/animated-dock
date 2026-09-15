import QtQuick
import qs.Commons
import qs.Ui

// One dock slot: a spacer rule, or a tile carrying a glyph or an icon.
//
// Everything stylistic comes off the plugin root (`dock`) so the item stays
// a pure view: measure, paint, report hover, forward taps. The two big
// differences from a plain dock slot are the fisheye and the interaction
// model:
//
//  • The cell's position and artwork scale are driven by the root's
//    continuous magnification (`dock.smoothScale` / `dock.smoothPos`),
//    which eases each cell toward the lens targets on a 16 ms loop while
//    the pointer is inside the dock. Positions never change during the
//    lens — the fishbowl zooms every icon in place over its base centre —
//    so the row, the card and its border hold perfectly still.
//    While nothing is magnified the cell follows the same base flow layout
//    (`dock.cellPos`) a static dock would use.
//
//  • A click on a running icon toggles minimize the dash2dock way: focus
//    the most-recently-used window, or minimize the whole app when it is
//    already focused. Scrolling the wheel over an icon cycles its windows.
//    Middle-click (or Ctrl+click on a trackpad) opens a new window.
Item {
  id: cell

  // The plugin root. Repeater fills modelData/index.
  required property var dock
  required property var modelData
  required property int index

  readonly property bool isSpacer: Util.isPlainObject(modelData) && modelData.spacer === true
  // The derived rule between the pinned and running sections. Drawn like a
  // spacer, slightly stronger, and just as inert.
  readonly property bool isDivider: Util.isPlainObject(modelData) && modelData.__divider === true
  readonly property bool isRule: isSpacer || isDivider
  // A synthesized running-section item (see RunningModel.extras).
  readonly property bool isRunning: Util.isPlainObject(modelData) && modelData.__running === true
  readonly property var entry: isRunning ? (modelData.__entry || null) : dock.desktopEntry(modelData)
  readonly property string label: dock.itemLabel(modelData, entry)
  // This item's live windows, MRU-first. Empty for launch-only items.
  readonly property var wins: isRule ? [] : dock.windowsFor(modelData)

  readonly property bool isApps: Util.isPlainObject(modelData) && modelData.showApps === true
  readonly property bool isTrash: Util.isPlainObject(modelData) && modelData.trash === true
  readonly property bool isStatic: isApps || isTrash

  // Whether this item's icon is colorized to the theme. Per-item `tint`
  // wins; monochrome forces tinting on, running-section items follow
  // tintRunning and pinned ones tintIcons. Glyphs are already ink-coloured
  // and ignore all of it. Trash fills/drains by its own palette.
  readonly property bool tinted: {
    var t = Util.isPlainObject(modelData) ? modelData.tint : undefined
    if (typeof t === "boolean") return t
    if (dock.monochrome) return true
    return isRunning ? dock.tintRunning : dock.tintIcons
  }
  // A Nerd Font glyph standing in for an icon file. Plenty of worthwhile
  // dock entries — a script, an RDP session, a kill switch — have no icon
  // on disk to point at.
  readonly property string glyph: {
    if (cell.isApps) return "󰀻"
    if (cell.isTrash) return "󰋬"
    return Util.isPlainObject(modelData) && modelData.glyph ? String(modelData.glyph) : ""
  }

  // Optical size correction for this item, clamped so a bad value can't
  // blow an icon out of the dock.
  readonly property real iconScale: {
    var n = Util.isPlainObject(modelData) ? Number(modelData.iconScale) : NaN
    return isFinite(n) && n > 0 ? Math.max(0.5, Math.min(1.6, n)) : 1.0
  }

  // Glyph ink is measurable, unlike an icon's alpha, so glyphs normalise
  // themselves: measure the tight bounding box at a reference size, then
  // pick the size that lands the ink at the target fraction of the slot.
  TextMetrics {
    id: glyphMetrics
    font.family: Style.font.resolvedFamily
    font.pixelSize: cell.dock.slot
    text: cell.glyph
  }

  readonly property int glyphSize: {
    var ink = glyphMetrics.tightBoundingRect.height
    if (!(ink > 0)) return Math.round(dock.slot * 0.66)
    var target = dock.slot * dock.glyphInkTarget * cell.iconScale
    return Math.max(1, Math.round(dock.slot * target / ink))
  }

  // The slot is `slot` across the dock and cellSize() along it.
  width:  dock.vertical ? dock.slot : dock.cellSize(modelData)
  height: dock.vertical ? dock.cellSize(modelData) : dock.slot

  // Placed by the dock's flow layout along the main axis. While dragged,
  // glued to the pointer instead, riding above the others. Under the
  // fisheye it settles on its magnified position; the Behaviour lets the
  // reflow glide instead of stepping.
  readonly property bool dragged: dock.dragging && dock.dragIndex === cell.index
  readonly property real pos: dragged
    ? dock.dragPointer - dock.dragGrabD
    : dock.smoothPos(cell.index)
  x: dock.vertical ? 0 : pos
  y: dock.vertical ? pos : 0
  z: dragged ? 10 : 0

  // Both the lens (root's easing loop) and the drag (dragPointer) already
  // smooth the cell's motion, so the Behaviour only needs to serve the idle
  // states: mounting, config reloads and the plain 1.12 hover magnify.
  Behavior on x {
    enabled: !cell.dragged && !cell.dock.fishSmoothing && !cell.dock.fisheyeActive
    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
  }
  Behavior on y {
    enabled: !cell.dragged && !cell.dock.fishSmoothing && !cell.dock.fisheyeActive
    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
  }

  Component.onCompleted: dock.registerCell(cell)
  Component.onDestruction: {
    dock.unregisterCell(cell)
    // A config reload can rebuild cells mid-drag; drop the drag rather
    // than act on a stale index.
    if (cell.dragged) dock.cancelDrag()
  }

  Rectangle {
    visible: cell.isRule
    anchors.centerIn: parent
    width:  cell.dock.vertical ? Math.round(cell.dock.slot * 0.6) : cell.dock.ruleWidth
    height: cell.dock.vertical ? cell.dock.ruleWidth : Math.round(cell.dock.slot * 0.6)
    color: Util.alpha(Color.popups.text, cell.isDivider ? 0.4 : 0.25)
  }

  // Tile and artwork share one parent so the fisheye scale moves them
  // together instead of the icon sliding around inside a stationary tile.
  // `x`/`y` replace anchors.centerIn so the lift can add its rise to the
  // centering: scaled icons translated out from the dock edge by a fraction
  // of their growth (Item has no `translate` facade — this is the QML way).
  Item {
    id: art
    visible: !cell.isRule
    width: cell.dock.slot
    height: cell.dock.slot

    // Notation: the artwork scale when the fisheye drives it, else falls
    // back to the plain hover magnify so a dock with magnify off never
    // pulses. The rise is the dash2dock "lift": scaled icons translate out
    // from the dock edge by a fraction of their growth.
    readonly property real hoverScale: (cell.dock.magnify && iconHover.hovered && !cell.dock.dragging && !cell.dock.fisheyeActive) ? 1.12 : 1.0
    readonly property real fishScale: cell.dock.fisheyeActive || cell.dock.fishSmoothing
      ? (cell.dock.smoothScale(cell.index) || 1.0) : 1.0
    scale: Math.max(cell.dock.fisheyeActive || cell.dock.fishSmoothing
      ? fishScale : hoverScale, 1.0)
    readonly property real growth: scale - 1.0

    // Cross-axis lift toward the screen edge, proportional to growth.
    readonly property real rise: growth * cell.dock.slot * cell.dock.zoomRaise
    transformOrigin: Item.Center
    x: (cell.width - width) / 2 + (cell.dock.vertical ? (cell.dock.edge === "left" ? rise : -rise) : 0)
    y: (cell.height - height) / 2 + (!cell.dock.vertical ? (cell.dock.edge === "top" ? rise : -rise) : 0)

    // During the lens, scale (and therefore the rise) comes from the dock's
    // per-frame loop, so the Behaviour steps aside rather than double easing
    // every target change with a fresh OutCubic restart. Idle, the plain
    // hover magnify stays a single 140 ms glide.
    Behavior on scale {
      enabled: !cell.dock.fisheyeActive && !cell.dock.fishSmoothing
      NumberAnimation { duration: dock.animMs; easing.type: Easing.OutCubic }
    }
    Behavior on x {
      enabled: !cell.dock.fisheyeActive && !cell.dock.fishSmoothing
      NumberAnimation { duration: dock.animMs; easing.type: Easing.OutCubic }
    }
    Behavior on y {
      enabled: !cell.dock.fisheyeActive && !cell.dock.fishSmoothing
      NumberAnimation { duration: dock.animMs; easing.type: Easing.OutCubic }
    }

    // The uniform container. Icons come in circles, squares and bare
    // glyphs; a tile behind every one of them is what makes a row of
    // mismatched artwork read as a single set.
    BorderSurface {
      id: tile
      visible: cell.dock.tiles
      anchors.fill: parent
      radius: cell.dock.tileRadiusPx
      color: Util.alpha(Color.popups.text, cell.dock.tileOpacity)
      borderSpec: Border.none()
    }

    // Inside a tile the artwork sits inset; without one it uses the whole
    // slot as before.
    readonly property int box: Math.round(
      cell.dock.slot * (cell.dock.tiles ? cell.dock.tileInset : 1.0) * cell.iconScale)

    Text {
      visible: cell.glyph !== ""
      anchors.centerIn: parent
      text: cell.glyph
      color: iconHover.hovered ? Color.accent : cell.dock.glyphColor
      Behavior on color { ColorAnimation { duration: 120 } }
      opacity: cell.dock.iconOpacity
      font.family: Style.font.resolvedFamily
      font.pixelSize: cell.dock.tiles
        ? Math.round(cell.glyphSize * cell.dock.tileInset)
        : cell.glyphSize
    }

    TintedIcon {
      visible: cell.glyph === ""
      anchors.centerIn: parent
      width: art.box
      height: art.box
      opacity: cell.dock.iconOpacity
      source: (cell.isRule || cell.glyph !== "") ? "" : cell.dock.itemIcon(cell.modelData, cell.entry)
      // Oversampled so the fisheye scale stays crisp on raster icons.
      sourceOversample: cell.dock.slot * 2
      tinted: cell.tinted
      ink: iconHover.hovered ? Color.accent : cell.dock.glyphColor
    }
  }

  // Drag-to-reorder (and, across the divider, drag-to-pin/unpin). The
  // handler's default activation threshold is what keeps a sloppy click a
  // click. target: null — the dock's flow layout owns all positioning.
  //
  // The fisheye is suppressed while dragging (dock.fisheyeActive turns off,
  // cells use the base flow layout in Dock.qml's cellPos), which is both
  // what lets a cell slide under the pointer and dash2dock's own _dragging
  // noAnimation mode.
  DragHandler {
    id: dragHandler
    enabled: !cell.isDivider && !cell.sweeping
    target: null
    xAxis.enabled: !(cell.holdMenu && cell.dock.vertical)
    yAxis.enabled: !(cell.holdMenu && !cell.dock.vertical)

    onActiveChanged: {
      if (active) cell.dock.beginDrag(cell, centroid.scenePosition.x, centroid.scenePosition.y)
      else cell.dock.endDrag()
    }

    onCentroidChanged: if (active) cell.dock.updateDrag(cell, centroid.scenePosition.x, centroid.scenePosition.y)
  }

  property bool holdMenu: false   // this press opened the menu
  property bool sweeping: false   // and the pointer has crossed into menu territory

  HoverHandler {
    id: iconHover
    enabled: !cell.isRule
    cursorShape: Qt.PointingHandCursor

    onHoveredChanged: {
      if (hovered) cell.dock.onIconHovered(cell)
      if (cell.dock.dragging) return
      if (hovered) {
        cell.dock.hoveredLabel = cell.label
        cell.dock.hoveredIndex = cell.index
        var c = cell.mapToItem(null, cell.width / 2, cell.height / 2)
        cell.dock.hoveredCenter = cell.dock.vertical ? c.y : c.x
      } else {
        if (cell.dock.hoveredLabel === cell.label) cell.dock.hoveredLabel = ""
        if (cell.dock.hoveredIndex === cell.index) cell.dock.hoveredIndex = -1
      }
    }

    Component.onDestruction: if (hovered && cell.dock.hoveredLabel === cell.label) cell.dock.hoveredLabel = ""
  }

  // Click: toggle-minimize. A running and focused app minimizes; a running
  // but unfocused one focuses its most-recently-used window; not running
  // launches. This is the dash2dock activate() model.
  TapHandler {
    enabled: !cell.isRule
    onTapped: if (!pinHover.hovered) cell.dock.activate(cell.modelData, cell.entry)

    // Click-and-hold is the trackpad-friendly route to the context menu
    // (macOS dock behaviour). Qt suppresses `tapped` on the release that
    // follows a long press, so holding never also launches.
    longPressThreshold: 0.5
    onLongPressed: {
      if (pinHover.hovered || cell.dock.dragging) return
      cell.dock.openMenu(cell)
      cell.holdMenu = cell.dock.menuOpen && cell.dock.menuIndex === cell.index
    }
  }

  // Middle-click, and Ctrl+click for the trackpad crowd (the dock layer
  // surface takes no keyboard focus, so Ctrl arrives unpressed; both are
  // here for whichever input lands). Both open a new window of the app.
  TapHandler {
    enabled: !cell.isRule
    acceptedButtons: Qt.MiddleButton
    onTapped: cell.dock.launchNewWindow(cell.modelData, cell.entry)
  }

  // Scroll over an icon cycles its windows (dash2dock's scroll-ccycle).
  // Steps accumulate across quiet deltas; each full step activates the next
  // window, and a transient label names it. With one window or a launch-only
  // icon, scrolling still pulses the label.
  WheelHandler {
    id: wheel
    enabled: !cell.isRule
    property real accum: 0

    onWheel: function(event) {
      var d = event.angleDelta.y || event.angleDelta.x
      if (d === 0) return
      wheel.accum += d / 120
      var steps = Math.trunc(wheel.accum)
      if (steps === 0) return
      wheel.accum -= steps
      cell.dock.cycleWindows(cell, steps)
    }
  }

  // Cross-axis sweep into the menu: with the menu up and the button still
  // down, motion past the card's inward face folds the menu off so the
  // pointer can run into it. (The PopupCard-style click-and-hold sweep
  // across the menu rows is dropped — a plain click moves the pointer and
  // this keeps the menu from swallowing the hold's release.) Simplified
  // from the parent dock: no row-wise sweep, just disable the drag past
  // the card face.
  PointHandler {
    id: holdPoint
    enabled: !cell.isRule
    acceptedButtons: Qt.LeftButton

    onPointChanged: {
      if (!active || !cell.holdMenu || cell.dock.dragging) return
      var win = cell.QsWindow.window
      if (!win) return
      var p = win.contentItem.mapFromItem(null, point.scenePosition.x, point.scenePosition.y)
      if (cell.dock.menuSweep(cell, win, p.x, p.y)) cell.sweeping = true
    }

    onActiveChanged: {
      if (active) return
      cell.holdMenu = false
      cell.sweeping = false
    }
  }

  // Pin badge: running-section items only, revealed by hover. One click
  // writes the item into items[] through the configurator CLI, and the
  // config reload moves the icon left of the divider — where it now stays.
  Rectangle {
    id: pinBadge
    readonly property bool shown: cell.isRunning && iconHover.hovered && !cell.dock.dragging
    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 120 } }

    width: Math.max(15, Math.round(cell.dock.slot * 0.4))
    height: width
    radius: width / 2
    anchors.right: art.right
    anchors.top: art.top
    anchors.rightMargin: Math.round(-width * 0.2)
    anchors.topMargin: Math.round(-height * 0.2)
    color: pinHover.hovered ? Color.accent : Util.alpha(Color.accent, 0.9)
    border.width: 1
    border.color: Color.popups.background

    Text {
      anchors.centerIn: parent
      text: "󰐃"
      color: Color.popups.background
      font.family: Style.font.resolvedFamily
      font.pixelSize: Math.round(parent.width * 0.62)
    }

    HoverHandler { id: pinHover; enabled: pinBadge.shown }
    TapHandler {
      enabled: pinBadge.shown
      onTapped: cell.dock.requestPin(cell.modelData)
    }
  }

  // Separate handler, left at the default (passive) gesture policy — the
  // old right-click menu died because ReleaseWithinBounds takes an
  // exclusive grab and starved the per-icon tap handlers.
  TapHandler {
    enabled: !cell.isRule
    acceptedButtons: Qt.RightButton
    onTapped: {
      cell.dock.openMenu(cell)
    }
  }

  // The running indicator: lit for any item with a live window — pinned or
  // not — in the theme accent. "dot" and "line" are the two shapes; "none"
  // turns it off. A focused app's window lights it brighter. It sits inside
  // the slot, on the side facing the screen edge, so lighting up never
  // reflows the dock.
  Rectangle {
    readonly property bool line: cell.dock.runningIndicator === "line"
    readonly property bool focused: cell.dock.hasActiveWindow(cell.modelData)
    readonly property int along: line ? Math.round(cell.dock.slot * 0.38) : 6
    readonly property int across: line ? 2 : 3
    visible: !cell.isRule && cell.dock.runningIndicator !== "none" && cell.wins.length > 0
    x: cell.dock.vertical
      ? (cell.dock.edge === "left" ? 2 : parent.width - width - 2)
      : Math.round((parent.width - width) / 2)
    y: cell.dock.vertical
      ? Math.round((parent.height - height) / 2)
      : (cell.dock.edge === "top" ? 2 : parent.height - height - 2)
    width:  cell.dock.vertical ? across : along
    height: cell.dock.vertical ? along : across
    radius: line ? 1 : 3
    color: focused ? Color.accent : Util.alpha(Color.accent, 0.45)
    Behavior on color { ColorAnimation { duration: 140 } }
  }

  // Count badge on grouped icons. It shares the top-right corner with the
  // pin badge, which only exists on hover — so the count yields to it then.
  Rectangle {
    readonly property bool shown: !cell.isRule && cell.wins.length > 1 && !pinBadge.shown
    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 120 } }

    height: Math.max(14, Math.round(cell.dock.slot * 0.32))
    width: Math.max(height, Math.round(countText.implicitWidth + height * 0.45))
    radius: height / 2
    anchors.right: art.right
    anchors.top: art.top
    anchors.rightMargin: Math.round(-height * 0.2)
    anchors.topMargin: Math.round(-height * 0.2)
    color: Color.accent
    border.width: 1
    border.color: Color.popups.background

    Text {
      id: countText
      anchors.centerIn: parent
      text: cell.wins.length
      color: Color.popups.background
      font.family: Style.font.resolvedFamily
      font.pixelSize: Math.round(parent.height * 0.68)
      font.bold: true
    }
  }
}