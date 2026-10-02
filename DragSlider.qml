import QtQuick
import qs.Commons
import qs.Ui

// Plugin-local slider for the dock's settings popup, based on qs.Ui's
// PanelSlider. Two deliberate departures from it:
//
//  • No mouse-wheel handler. The shared component wheels to adjust a value
//    (used by the audio panels), but here the slider lives inside a
//    scrollable settings popup, so wheeling to scroll the page must never
//    nudge the value under the cursor. Wheel events over this slider are not
//    handled, so they bubble up to the ScrollView and scroll the page; the
//    value only moves by click-and-drag.
//
//  • `step` is actually applied, and the released value is held until the
//    write comes back. PanelSlider leaves both to its caller, which is
//    invisible when the value is held in memory but not when every edit
//    round-trips through a configurator process and a config file reload.
Item {
  id: root

  property QtObject bar: null
  property real value: 0
  property real minimum: 0
  property real maximum: 1
  // Detents along the track. A step of 0 (or 1) means "continuous"; anything
  // larger quantises the value to multiples of it, measured from `minimum`.
  property real step: 0.05
  property bool integer: false
  property color trackColor: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "#333"
  property color fillColor: bar ? bar.foreground : Color.foreground
  property color knobColor: bar ? bar.foreground : Color.foreground
  property bool dragging: false
  property real trackHeight: Math.max(4, Math.round(Style.spacing.controlHeight * 0.11))
  property real knobSize: Math.max(14, Math.round(Style.spacing.controlHeight * 0.38))
  property real liveValue: value

  // macOS-style notches. When > 1, that many evenly-spaced tick marks are cut
  // into the track (drawn in the panel background color, so only the part
  // crossing the track shows). Default 0 leaves the track plain.
  property int tickCount: 0
  property color tickColor: bar ? bar.background : Color.background

  // The written value comes back through the settings popup, and only after a
  // configurator run has rewritten shell.json and the shell has re-read it.
  // Snapping `liveValue` to `value` on release would animate the knob all the
  // way back to the pre-drag number and then jump forward again a frame or two
  // later, so the dragged value is held instead — with a watchdog underneath
  // it: if the write never comes back (the configurator died), fall back to
  // what the config actually holds rather than leaving the knob lying.
  Timer {
    id: settle
    interval: 1500
    onTriggered: if (!root.dragging && root.liveValue !== root.value) root.liveValue = root.value
  }

  onValueChanged: {
    if (dragging) return
    liveValue = value
    settle.stop()
  }

  signal moved(real value)
  signal released(real value)

  implicitWidth: Style.space(200)
  implicitHeight: Math.max(Style.space(22), knobSize + Style.spacing.md)

  readonly property real range: Math.max(0.0001, maximum - minimum)
  readonly property real progress: Math.max(0, Math.min(1, (liveValue - minimum) / range))
  readonly property bool _hot: mouseArea.containsMouse || root.dragging

  Rectangle {
    id: track
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.right: parent.right
    height: root.trackHeight
    radius: height / 2
    color: root.trackColor
  }

  Rectangle {
    id: fill
    anchors.verticalCenter: track.verticalCenter
    anchors.left: track.left
    height: track.height
    radius: track.radius
    color: root.fillColor
    width: track.width * root.progress

    Behavior on width {
      enabled: !root.dragging
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
  }

  Repeater {
    model: root.tickCount > 1 ? root.tickCount : 0
    Rectangle {
      required property int index
      width: Math.max(1, Style.space(2))
      height: root.trackHeight + Style.space(4)
      radius: 1
      color: root.tickColor
      anchors.verticalCenter: track.verticalCenter
      x: Math.max(0, Math.min(track.width - width,
                              track.width * (index / (root.tickCount - 1)) - width / 2))
    }
  }

  BorderSurface {
    id: knob
    width: root.knobSize
    height: root.knobSize
    radius: root.knobSize / 2
    color: root.knobColor
    borderSpec: Border.flat(root.bar ? root.bar.background : "#101315", Math.max(1, Style.space(2)))
    anchors.verticalCenter: track.verticalCenter
    x: Math.max(0, Math.min(track.width - width, track.width * root.progress - width / 2))
    scale: root._hot ? 1.15 : 1.0

    Behavior on x {
      enabled: !root.dragging
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    Behavior on scale {
      NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton

    function valueFromX(x) {
      var clamped = Math.max(0, Math.min(track.width, x))
      var raw = root.minimum + (clamped / track.width) * root.range
      // Snap to the caller's detents. `step` is honoured here rather than
      // left to the caller: the dock's sliders declare steps of 2 px / 5%
      // and were quietly producing values like 39 px and 47%.
      if (root.step > 0 && root.step < root.range)
        raw = root.minimum + Math.round((raw - root.minimum) / root.step) * root.step
      if (root.integer) raw = Math.round(raw)
      return Math.max(root.minimum, Math.min(root.maximum, raw))
    }

    onPressed: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      root.dragging = true
      var next = valueFromX(mouse.x)
      root.liveValue = next
      root.moved(next)
    }
    onPositionChanged: function(mouse) {
      if (!root.dragging) return
      var next = valueFromX(mouse.x)
      root.liveValue = next
      root.moved(next)
    }
    onReleased: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      root.dragging = false
      var v = root.liveValue
      root.released(v)
      settle.start()
    }
  }
}
