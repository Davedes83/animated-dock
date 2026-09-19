import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Settings panel for the dock, opened from the Omarchy Menu icon's
// right-click "Settings" row. A plain unanchored layer-shell surface —
// wlr-layer-shell auto-centres a surface on any axis it has no anchor on
// (the same rule Dock.qml's own windows use), so with *no* anchors set at
// all this is centred on both axes, on whatever monitor it targets, always.
//
// This used to be a PopupWindow anchored to the dock window's icon, with
// its position captured once and re-derived against the dock's *current*
// geometry on every anchoring pass. That never worked across an edge
// change: picking a new edge relocates the dock to a different side of the
// screen and swaps its width/height, and re-deriving a point meant for the
// old window against the new one routinely landed far outside it — a
// popup's positioner is fundamentally relative to (and constrained near)
// its parent surface, so there was no way to reliably plant it at an
// arbitrary screen point that way. A plain centred top-level window sits
// outside that whole problem: it isn't relative to the dock at all.
//
// Held open the same way as before: a HyprlandFocusGrab routes input to
// this window and the dock, so clicking anywhere else clears the grab and
// the panel closes. Every control writes through the bundled configurator's
// `set` subcommand (typed JSON), and the shell hot-reloads shell.json on
// save, so changes land live.
PanelWindow {
  id: settings

  required property var dock

  property var anchorCell: null
  property bool open: false
  // Border radius captured on open: matching the dock's current shape without
  // chasing cardRadius live (which changes with icon size in pill mode).
  property int lockRadius: Style.cornerRadius

  function openFor(cell) {
    settings.anchorCell = cell
    settings.lockRadius = Math.min(settings.dock.cardRadius, Style.cornerRadius)
    if (!settings.open) {
      settings.open = true
      settings.dock.holdForPopup()
    }
  }

  function anchorWindowScreenName() {
    var target = settings.anchorCell
    var window = target ? target.QsWindow.window : null
    if (window && window.screen) return String(window.screen.name || "")
    return ""
  }

  function close() {
    if (!settings.open) return
    settings.open = false
    settings.dock.popupReleased()
  }

  screen: {
    var name = settings.anchorWindowScreenName()
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].name || "") === name) return list[i]
    }
    return list.length > 0 ? list[0] : null
  }

  visible: open
  color: "transparent"
  WlrLayershell.namespace: "omarchy-animated-dock-settings"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0
  // No anchors set on any edge — centred on both axes automatically.

  readonly property int pad: Style.spacing.md
  readonly property int contentWidth: Style.space(300)
  readonly property var settingsBorder: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))

  implicitWidth: contentWidth + pad * 2 + Border.left(settingsBorder) + Border.right(settingsBorder)
  implicitHeight: Math.round(column.implicitHeight + pad * 2 + Border.top(settingsBorder) + Border.bottom(settingsBorder))
  width: implicitWidth
  height: implicitHeight

  HyprlandFocusGrab {
    active: settings.open
    windows: {
      var out = [settings]
      var w = settings.anchorCell ? settings.anchorCell.QsWindow.window : null
      if (w) out.push(w)
      return out
    }
    onCleared: settings.close()
  }

  BorderSurface {
    id: card
    anchors.fill: parent
    radius: settings.lockRadius
    color: Util.alpha(Color.popups.background, 0.97)
    borderSpec: settings.settingsBorder

    Column {
      id: column
      x: Border.left(settings.settingsBorder) + settings.pad
      y: Border.top(settings.settingsBorder) + settings.pad
      width: settings.contentWidth
      spacing: Style.spacing.lg

      Row {
        width: settings.contentWidth
        spacing: Style.spacing.md

        Text {
          width: settings.contentWidth - Style.space(40) - Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          text: "Dock Settings"
          color: Color.popups.text
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Button {
          anchors.verticalCenter: parent.verticalCenter
          iconText: "✕"
          fontSize: Style.font.body
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          foreground: Color.popups.text
          accent: Color.accent
          onClicked: settings.close()
        }
      }

      Column {
        width: settings.contentWidth
        spacing: Style.spacing.xs

        Row {
          width: settings.contentWidth
          spacing: Style.spacing.md

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Icon Size"
            color: Color.popups.text
            font.family: Style.font.resolvedFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: String(Math.round(sizeSlider.liveValue)) + " px"
            color: Util.alpha(Color.popups.text, 0.6)
            font.family: Style.font.resolvedFamily
            font.pixelSize: Style.font.caption
          }
        }

        PanelSlider {
          id: sizeSlider
          width: settings.contentWidth
          minimum: 24
          maximum: 96
          step: 2
          integer: true
          value: settings.dock.num("iconSize", 44)
          fillColor: Color.accent
          knobColor: Color.accent
          onReleased: function(v) {
            settings.dock.applySetting("iconSize", String(Math.round(v)))
          }
        }
      }

      Toggle {
        id: autohideToggle
        width: settings.contentWidth
        label: "Auto-hide"
        description: "Slide the dock off-screen until the edge is brushed."
        checked: settings.dock.flag("autohide", true)
        foreground: Color.popups.text
        accent: Color.accent
        onClicked: settings.dock.applySetting("autohide", String(!settings.dock.flag("autohide", true)))
      }

      Toggle {
        id: borderToggle
        width: settings.contentWidth
        label: "Border"
        description: "Outline around the dock card."
        checked: settings.dock.flag("border", true)
        foreground: Color.popups.text
        accent: Color.accent
        onClicked: settings.dock.applySetting("border", String(!settings.dock.flag("border", true)))
      }

      Column {
        width: settings.contentWidth
        spacing: Style.spacing.xs

        Row {
          width: settings.contentWidth
          spacing: Style.spacing.md

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Border opacity"
            color: Color.popups.text
            font.family: Style.font.resolvedFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(borderOpacitySlider.liveValue) + "%"
            color: Util.alpha(Color.popups.text, 0.6)
            font.family: Style.font.resolvedFamily
            font.pixelSize: Style.font.caption
          }
        }

        PanelSlider {
          id: borderOpacitySlider
          width: settings.contentWidth
          minimum: 0
          maximum: 100
          step: 5
          integer: true
          value: Math.round(settings.dock.fraction("borderOpacity", 1.0) * 100)
          fillColor: Color.accent
          knobColor: Color.accent
          onReleased: function(v) {
            settings.dock.applySetting("borderOpacity", String(v / 100))
          }
        }
      }

      Column {
        width: settings.contentWidth
        spacing: Style.spacing.xs

        Row {
          width: settings.contentWidth
          spacing: Style.spacing.md

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Background opacity"
            color: Color.popups.text
            font.family: Style.font.resolvedFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(bgOpacitySlider.liveValue) + "%"
            color: Util.alpha(Color.popups.text, 0.6)
            font.family: Style.font.resolvedFamily
            font.pixelSize: Style.font.caption
          }
        }

        PanelSlider {
          id: bgOpacitySlider
          width: settings.contentWidth
          minimum: 0
          maximum: 100
          step: 5
          integer: true
          value: Math.round(settings.dock.fraction("backgroundOpacity", 1.0) * 100)
          fillColor: Color.accent
          knobColor: Color.accent
          onReleased: function(v) {
            settings.dock.applySetting("backgroundOpacity", String(v / 100))
          }
        }
      }

      Column {
        width: settings.contentWidth
        spacing: Style.spacing.sm

        Text {
          width: settings.contentWidth
          text: "Position"
          color: Color.popups.text
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.bodySmall
        }

        ButtonGroup {
          options: [
            { value: "bottom", label: "Bottom" },
            { value: "top", label: "Top" },
            { value: "left", label: "Left" },
            { value: "right", label: "Right" }
          ]
          value: settings.dock.edge
          foreground: Color.popups.text
          background: Color.popups.background
          accent: Color.accent
          onChanged: function(v) {
            settings.dock.applySetting("edge", JSON.stringify(String(v)))
          }
        }
      }

      Toggle {
        id: fullWidthToggle
        width: settings.contentWidth
        label: "Full length"
        description: "Span the whole edge of the screen."
        checked: settings.dock.flag("fullWidth", false)
        foreground: Color.popups.text
        accent: Color.accent
        onClicked: settings.dock.applySetting("fullWidth", String(!settings.dock.flag("fullWidth", false)))
      }

      Column {
        width: settings.contentWidth
        spacing: Style.spacing.sm

        Text {
          width: settings.contentWidth
          text: "Corner Shape"
          color: Color.popups.text
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.bodySmall
        }

        ButtonGroup {
          options: [
            { value: "rounded", label: "Rounded" },
            { value: "square", label: "Square" },
            { value: "pill", label: "Pill" }
          ]
          value: settings.dock.cornerShape
          foreground: Color.popups.text
          background: Color.popups.background
          accent: Color.accent
          onChanged: function(v) {
            settings.dock.applySetting("cornerShape", JSON.stringify(String(v)))
          }
        }
      }

      Toggle {
        id: tooltipsToggle
        width: settings.contentWidth
        label: "Show icon name on hover"
        description: "Show the icon's name when hovering over it."
        checked: settings.dock.flag("tooltips", true)
        foreground: Color.popups.text
        accent: Color.accent
        onClicked: settings.dock.applySetting("tooltips", String(!settings.dock.flag("tooltips", true)))
      }

      Column {
        width: settings.contentWidth
        spacing: Style.spacing.sm

        Text {
          width: settings.contentWidth
          text: "Support"
          color: Color.popups.text
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.bodySmall
        }

        Button {
          width: settings.contentWidth
          iconText: "☕"
          text: "Support me on Ko-fi"
          foreground: Color.popups.text
          accent: Color.accent
          onClicked: {
            settings.close()
            Util.execDetached("xdg-open https://ko-fi.com/davedes")
          }
        }
      }
    }
  }
}