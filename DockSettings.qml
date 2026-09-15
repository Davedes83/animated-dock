import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Settings popup for the dock, opened from the Omarchy Menu icon's
// right-click "Settings" row. Anchored exactly like the context menu and
// held open the same way: a HyprlandFocusGrab routes input to the window
// and the dock, so clicking anywhere else clears the grab and the popup
// closes. Every control writes through the bundled configurator's `set`
// subcommand (typed JSON), and the shell hot-reloads shell.json on save,
// so changes land live.
PopupWindow {
  id: settings

  required property var dock

  property var anchorCell: null
  property bool open: false

  function openFor(cell) {
    settings.anchorCell = cell
    if (settings.open) {
      settings.anchor.updateAnchor()
      return
    }
    settings.open = true
    settings.dock.holdForPopup()
  }

  function close() {
    if (!settings.open) return
    settings.open = false
    settings.dock.popupReleased()
  }

  visible: open
  color: "transparent"

  readonly property int pad: Style.spacing.md
  readonly property int contentWidth: Style.space(300)
  readonly property var settingsBorder: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))

  implicitWidth: contentWidth + pad * 2 + Border.left(settingsBorder) + Border.right(settingsBorder)
  implicitHeight: Math.round(column.implicitHeight + pad * 2 + Border.top(settingsBorder) + Border.bottom(settingsBorder))

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

  anchor {
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: settings.dock.popupGravity
    window: settings.anchorCell ? settings.anchorCell.QsWindow.window : null

    onAnchoring: {
      var target = settings.anchorCell
      var window = target ? target.QsWindow.window : null
      if (!window) return
      var p = settings.dock.popupAnchorPoint(target, window, settings.implicitWidth, settings.implicitHeight)
      anchor.rect.x = p.x
      anchor.rect.y = p.y
      anchor.rect.width = 1
      anchor.rect.height = 1
    }
  }

  BorderSurface {
    id: card
    anchors.fill: parent
    radius: Math.min(settings.dock.cardRadius, Style.cornerRadius)
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
    }
  }
}