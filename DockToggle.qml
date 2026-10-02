import QtQuick
import qs.Ui

// The shell's Toggle with the one thing it deliberately leaves out: an honest
// optimistic state.
//
// Toggle is stateless by design — `checked` is bound straight to the config,
// and the config only catches up once the configurator has rewritten
// shell.json and the shell has re-read it: tens of milliseconds. A second
// click inside that window reads the same `checked` and writes the same value
// again, so a quick double-click (or two taps of the space bar) lands as a
// no-op. This wrapper counts the flips the user has asked for and layers them
// over the stored value, so every click counts exactly once, and drops the
// count the moment the real value moves — a write that never lands snaps back
// on its own instead of leaving the switch lying.
//
// `checked` is a binding all the way through (never assigned), so the config
// stays the single source of truth.
Item {
  id: root

  // What the config says right now.
  required property bool stored

  // Optimistic flips the user has made since the stored value last moved:
  // an odd count shows the stored value inverted, an even count (two quick
  // clicks) shows it as-is. Parity, not a boolean — `stored` cannot change
  // under the second click, so neither can a flag.
  property int flips: 0
  readonly property bool pending: (flips % 2 === 1) ? !stored : stored

  // Emitted with the value to persist — the absolute value, never a delta,
  // because the configurator is the one that re-reads the file.
  signal requestWrite(bool value)

  property string label: ""
  property string description: ""
  property color foreground: Color.popups.text
  property color accent: Color.accent

  implicitWidth: toggle.implicitWidth
  implicitHeight: toggle.implicitHeight

  onStoredChanged: root.flips = 0

  Toggle {
    id: toggle
    anchors.fill: parent
    label: root.label
    description: root.description
    checked: root.pending
    foreground: root.foreground
    accent: root.accent

    onClicked: {
      root.flips++
      root.requestWrite(root.pending)
    }
  }
}
