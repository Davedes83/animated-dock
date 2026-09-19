import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Settings popup for the dock, opened from the Omarchy Menu icon's
// right-click "Settings" row. Anchored exactly like the context menu and
// held open the same way: a HyprlandFocusGrab routes input to the window
// and the dock, so clicking anywhere else clears the grab and the popup
// closes. Controls are grouped under five uppercase section headers —
// Appearance, Glow, Behaviour, Taskbar sync, Support — each toggle sitting
// with its dependent control. Every control writes through the bundled
// configurator (the `set` subcommand or the atomic `opacity` /
// `corner-shape` / `glow`-family pushes that mirror the taskbar in the same
// write), and the shell hot-reloads shell.json on save, so changes land live.
PopupWindow {
  id: settings

  required property var dock

  property var anchorCell: null
  property bool open: false
  // Screen position captured on open, so edits that resize the dock card
  // (icon size, shape) can't re-anchor the popup and make it jump under the
  // mouse. The dock window has no QML x/y, so its on-screen origin is derived
  // from edge/align/fullWidth and monitor geometry (windowScreenRect), and
  // the open-time anchor rect is stored in local terms too. onAnchoring
  // re-derives the local rect from the current window origin so the popup
  // stays glued to the screen point it opened on. Stale writes are skipped —
  // re-committing a popup position every animation frame is what flickers its
  // border.
  property bool locked: false
  property real lockRX: 0
  property real lockRY: 0
  property real lockScreenX: 0
  property real lockScreenY: 0
  // Border radius captured on open: matching the dock's current shape without
  // chasing cardRadius live (which changes with icon size in pill mode).
  property int lockRadius: Style.cornerRadius

  function openFor(cell) {
    settings.anchorCell = cell
    settings.lockAtAnchor()
    if (settings.open) {
      settings.anchor.updateAnchor()
      return
    }
    settings.open = true
    settings.dock.holdForPopup()
  }

  function anchorWindowScreenName() {
    var target = settings.anchorCell
    var window = target ? target.QsWindow.window : null
    if (window && window.screen) return String(window.screen.name || "")
    return ""
  }

  function lockAtAnchor() {
    var target = settings.anchorCell
    var window = target ? target.QsWindow.window : null
    if (!window) return
    var p = settings.dock.popupAnchorPoint(target, window, settings.implicitWidth, settings.implicitHeight, true)
    settings.lockRX = p.x
    settings.lockRY = p.y
    var wsr = settings.dock.windowScreenRect(settings.anchorWindowScreenName())
    if (wsr) {
      settings.lockScreenX = wsr.x + p.x
      settings.lockScreenY = wsr.y + p.y
    } else {
      settings.lockScreenX = p.x
      settings.lockScreenY = p.y
    }
    settings.lockRadius = Math.min(settings.dock.cardRadius, Style.cornerRadius)
    settings.locked = true
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

  // The body scrolls inside a fixed cap, so adding rows later never makes
  // the popup walk up off the screen. When the column fits the cap the box
  // hugs it (no scrollbar); above it, the box stays put and the column
  // scrolls. The cap tracks the monitor so a small screen still fits.
  readonly property int bodyHeight: Math.min(column.implicitHeight, maxBodyHeight)
  readonly property int maxBodyHeight: {
    var m = settings.dock.monitorRect(settings.anchorWindowScreenName())
    if (m) return Math.max(Style.space(280), Math.min(Style.space(620), Math.round(m.height) - Style.space(80)))
    return Style.space(620)
  }

  implicitWidth: contentWidth + pad * 2 + Border.left(settingsBorder) + Border.right(settingsBorder)
  // Pinned to the implicit width so a live value label ("42 px") can never
  // reflow the box. The dock window is frozen (resized to the slider's max)
  // while this popup is open, so nothing below ever re-sizes it.
  width: contentWidth + pad * 2 + Border.left(settingsBorder) + Border.right(settingsBorder)
  implicitHeight: Math.round(settings.bodyHeight + pad * 2 + Border.top(settingsBorder) + Border.bottom(settingsBorder))

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
      if (!settings.locked) return
      var wsr = settings.dock.windowScreenRect(settings.anchorWindowScreenName())
      if (!wsr) return
      var nx = settings.lockScreenX - wsr.x
      var ny = settings.lockScreenY - wsr.y
      if (nx === anchor.rect.x && ny === anchor.rect.y) return
      anchor.rect.x = nx
      anchor.rect.y = ny
      anchor.rect.width = 1
      anchor.rect.height = 1
    }
  }

  BorderSurface {
    id: card
    anchors.fill: parent
    radius: settings.lockRadius
    color: Util.alpha(Color.popups.background, 0.97)
    borderSpec: settings.settingsBorder

    ScrollView {
      id: scroll
      x: Border.left(settings.settingsBorder) + settings.pad
      y: Border.top(settings.settingsBorder) + settings.pad
      width: settings.contentWidth
      height: settings.bodyHeight
      clip: true
      contentWidth: availableWidth
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical.policy: column.implicitHeight > scroll.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

      Column {
        id: column
        width: scroll.availableWidth
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

      PanelSeparator {
        foreground: Color.popups.text
      }

      PanelSectionHeader {
        text: "APPEARANCE"
        foreground: Color.popups.text
        fontFamily: Style.font.resolvedFamily
        color: Color.popups.text
        fontSize: Style.font.body
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

        DragSlider {
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

        DragSlider {
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
            Util.execDetached(settings.dock.configCmd + " opacity " + Util.shellQuote(String(v / 100)))
          }
        }
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
            Util.execDetached(settings.dock.configCmd + " corner-shape " + Util.shellQuote(String(v)))
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

        DragSlider {
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

      PanelSeparator {
        foreground: Color.popups.text
      }

      PanelSectionHeader {
        text: "GLOW"
        foreground: Color.popups.text
        fontFamily: Style.font.resolvedFamily
        color: Color.popups.text
        fontSize: Style.font.body
      }

      Toggle {
        id: glowToggle
        width: settings.contentWidth
        label: "Border glow"
        description: "Soft halo blooming out from the dock's border."
        checked: settings.dock.flag("glow", false)
        foreground: Color.popups.text
        accent: Color.accent
        onClicked: {
          var next = !settings.dock.flag("glow", false)
          Util.execDetached(settings.dock.configCmd
            + " glow " + (next ? "true" : "false"))
        }
      }

      Column {
        width: settings.contentWidth
        spacing: Style.spacing.lg
        visible: settings.dock.flag("glow", false)

        Column {
          width: settings.contentWidth
          spacing: Style.spacing.xs

          Row {
            width: settings.contentWidth
            spacing: Style.spacing.md

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Glow strength"
              color: Color.popups.text
              font.family: Style.font.resolvedFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: Math.round(glowStrengthSlider.liveValue) + "%"
              color: Util.alpha(Color.popups.text, 0.6)
              font.family: Style.font.resolvedFamily
              font.pixelSize: Style.font.caption
            }
          }

          DragSlider {
            id: glowStrengthSlider
            width: settings.contentWidth
            minimum: 0
            maximum: 100
            step: 5
            integer: true
            value: Math.round(settings.dock.fraction("glowAmount", 0.5) * 100)
            fillColor: Color.accent
            knobColor: Color.accent
            onReleased: function(v) {
            Util.execDetached(settings.dock.configCmd + " glow-amount " + Util.shellQuote(String(v / 100)))
          }
          }
        }

        Column {
          width: settings.contentWidth
          spacing: Style.spacing.sm

          Text {
            width: settings.contentWidth
            text: "Glow focus"
            color: Color.popups.text
            font.family: Style.font.resolvedFamily
            font.pixelSize: Style.font.bodySmall
          }

          ButtonGroup {
            options: [
              { value: "full", label: "Full" },
              { value: "top", label: "Top" },
              { value: "bottom", label: "Bottom" }
            ]
            value: {
              var focus = String(settings.dock.config.glowFocus || "")
              return (focus === "bottom" || focus === "top") ? focus : "full"
            }
            foreground: Color.popups.text
            background: Color.popups.background
            accent: Color.accent
            onChanged: function(v) {
              Util.execDetached(settings.dock.configCmd + " glow-focus " + Util.shellQuote(String(v)))
            }
          }
        }
      }

      PanelSeparator {
        foreground: Color.popups.text
      }

      PanelSectionHeader {
        text: "BEHAVIOUR"
        foreground: Color.popups.text
        fontFamily: Style.font.resolvedFamily
        color: Color.popups.text
        fontSize: Style.font.body
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
        id: tooltipsToggle
        width: settings.contentWidth
        label: "Show icon name on hover"
        description: "Show the icon's name when hovering over it."
        checked: settings.dock.flag("tooltips", true)
        foreground: Color.popups.text
        accent: Color.accent
        onClicked: settings.dock.applySetting("tooltips", String(!settings.dock.flag("tooltips", true)))
      }

      PanelSeparator {
        foreground: Color.popups.text
      }

      PanelSectionHeader {
        text: "TASKBAR SYNC"
        foreground: Color.popups.text
        fontFamily: Style.font.resolvedFamily
        color: Color.popups.text
        fontSize: Style.font.body
      }

      Toggle {
        id: matchBarOpacityToggle
        width: settings.contentWidth
        label: "Sync taskbar opacity"
        description: "Make the taskbar's background as opaque as the dock's."
        checked: settings.dock.flag("matchBarOpacity", false)
        foreground: Color.popups.text
        accent: Color.accent
        onClicked: {
          var next = !settings.dock.flag("matchBarOpacity", false)
          Util.execDetached(settings.dock.configCmd
            + " matchbar-opacity " + (next ? "true" : "false"))
        }
      }

      Toggle {
        id: matchBarCornersToggle
        width: settings.contentWidth
        label: "Sync taskbar corners"
        description: "Give the taskbar the dock's corner shape (rounded, square or pill)."
        checked: settings.dock.flag("matchBarCorners", false)
        foreground: Color.popups.text
        accent: Color.accent
        onClicked: {
          var next = !settings.dock.flag("matchBarCorners", false)
          Util.execDetached(settings.dock.configCmd
            + " matchbar-corners " + (next ? "true" : "false"))
        }
      }

      Toggle {
        id: matchBarGlowToggle
        width: settings.contentWidth
        label: "Sync taskbar glow"
        description: "Give the taskbar the dock's border glow."
        checked: settings.dock.flag("matchBarGlow", false)
        foreground: Color.popups.text
        accent: Color.accent
        onClicked: {
          var next = !settings.dock.flag("matchBarGlow", false)
          Util.execDetached(settings.dock.configCmd
            + " matchbar-glow " + (next ? "true" : "false"))
        }
      }

      PanelSeparator {
        foreground: Color.popups.text
      }

      PanelSectionHeader {
        text: "SUPPORT"
        foreground: Color.popups.text
        fontFamily: Style.font.resolvedFamily
        color: Color.popups.text
        fontSize: Style.font.body
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
}