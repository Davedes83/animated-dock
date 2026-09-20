import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Who is running, and which dock item owns them.
//
// Everything live-window behaviour does — the running dot, click-to-focus,
// the unpinned section, pinning, grouping — reduces to one question: which
// toplevels does a dock item match? The answer is keyed on the Wayland
// appId (Hyprland "class"), resolved per item as:
//
//   1. item.appId          explicit override, string or array; wins outright
//   2. entry.startupClass  the desktop entry's StartupWMClass, when set
//   3. the desktop id      the well-behaved case (org.gnome.Nautilus)
//
// Comparison is case-insensitive. Exact strings always match; a tail match
// ("nautilus" vs "org.gnome.Nautilus") is only tried when exactly one side is
// unqualified, i.e. the window only reports a bare class, because apps are
// sloppy here. Two fully-qualified ids never collide by last segment.
//
// The running section is *derived* state: grouped toplevels whose appId no
// pinned item claims. It is never written to shell.json.
Item {
  id: model
  visible: false

  // The plugin root, for desktopEntry() lookups on pinned items.
  required property var dock
  // items[] from shell.json — the pinned half of the dock.
  required property var pinnedItems

  // Apps set their appId a beat after the window maps, and Quickshell's
  // values list doesn't re-notify for it. Bumped by the per-toplevel
  // watchers below so the group binding re-evaluates.
  property int rev: 0

  // Most-recently-used order, newest first, as toplevel references. Pruned
  // against the live toplevel set so closed windows' references don't
  // accumulate through a long session; only live windows ever contribute to
  // grouping/sorting order anyway.
  property var mru: []

  // Drop entries for toplevels no longer mapped. Bounded by the live window
  // count, so a long session can't accumulate stale references.
  function pruneMru() {
    var vals = ToplevelManager.toplevels.values || []
    model.mru = model.mru.filter(function(t) { return vals.indexOf(t) >= 0 })
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() {
      var t = ToplevelManager.activeToplevel
      if (!t) return
      var next = [t]
      for (var i = 0; i < model.mru.length; i++)
        if (model.mru[i] !== t) next.push(model.mru[i])
      model.mru = next
      model.pruneMru()
    }
  }

  // Windows can close without ever being active again, so also prune on a
  // low-frequency timer rather than only when focus moves.
  Timer {
    interval: 30000
    repeat: true
    triggeredOnStart: true
    onTriggered: model.pruneMru()
  }

  Instantiator {
    model: ToplevelManager.toplevels.values || []
    delegate: Connections {
      required property var modelData
      target: modelData
      function onAppIdChanged() { model.rev++ }
    }
  }

  // ------------------------------------------------------------- matching

  function canon(s) { return String(s || "").toLowerCase() }

  // "org.gnome.Nautilus" vs "nautilus": exact always wins, and a tail match
  // is only acceptable when exactly one side is bare — the window reported
  // nothing but a class, so its full id is unavailable. Two qualified ids
  // never match by last segment, so "foo.bar" cannot be grouped with an
  // unrelated "bar" that happens to share a tail.
  function idMatch(a, b) {
    a = canon(a); b = canon(b)
    if (!a || !b) return false
    if (a === b) return true
    var aDot = a.indexOf(".") >= 0
    var bDot = b.indexOf(".") >= 0
    if (aDot === bDot) return false
    var long = aDot ? a : b
    var short = aDot ? b : a
    return long.slice(long.lastIndexOf(".") + 1) === short
  }

  function matchKeys(item) {
    if (!Util.isPlainObject(item) || item.spacer === true || item.__divider === true) return []
    if (item.appId !== undefined) {
      var raw = Array.isArray(item.appId) ? item.appId : [item.appId]
      var keys = []
      for (var i = 0; i < raw.length; i++) if (raw[i]) keys.push(String(raw[i]))
      return keys
    }
    var out = []
    var entry = dock.desktopEntry(item)
    if (entry && entry.startupClass) out.push(String(entry.startupClass))
    if (item.desktop) out.push(String(item.desktop).replace(/\.desktop$/, ""))
    return out
  }

  // --------------------------------------------------------------- groups

  // appId (canonical) -> [toplevels], in list order. Windows that never
  // report an appId are unidentifiable and skipped.
  readonly property var groups: {
    void model.rev
    var vals = ToplevelManager.toplevels.values || []
    var out = {}
    for (var i = 0; i < vals.length; i++) {
      var id = canon(vals[i].appId)
      if (!id) continue
      if (!out[id]) out[id] = []
      out[id].push(vals[i])
    }
    return out
  }

  // The item's live windows, most-recently-used first.
  function windowsFor(item) {
    var keys = matchKeys(item)
    if (keys.length === 0) return []
    var wins = []
    for (var gid in groups) {
      for (var k = 0; k < keys.length; k++) {
        if (idMatch(keys[k], gid)) { wins = wins.concat(groups[gid]); break }
      }
    }
    if (wins.length < 2) return wins
    var order = model.mru
    wins.sort(function(a, b) {
      var ia = order.indexOf(a), ib = order.indexOf(b)
      return (ia === -1 ? 1e9 : ia) - (ib === -1 ? 1e9 : ib)
    })
    return wins
  }

  // Desktop entry for a bare appId, for the running section's icon and
  // label. heuristicLookup handles the messy real-world cases; the manual
  // scan backstops it with the same canonical compare used everywhere else.
  function entryFor(appId) {
    var e = null
    try { e = DesktopEntries.heuristicLookup(appId) } catch (err) { e = null }
    if (e) return e
    var values = (DesktopEntries.applications && DesktopEntries.applications.values) || []
    for (var i = 0; i < values.length; i++) {
      var id = String(values[i].id || "").replace(/\.desktop$/, "")
      if (idMatch(id, appId)) return values[i]
    }
    return null
  }

  // Running-but-not-pinned, as synthesized dock items. An app with no
  // desktop entry still shows — generic glyph, appId for a label — since
  // "it is running" is the whole point of the section.
  readonly property var extras: {
    var claimedKeys = []
    var list = Array.isArray(pinnedItems) ? pinnedItems : []
    for (var i = 0; i < list.length; i++)
      claimedKeys = claimedKeys.concat(matchKeys(list[i]))

    var out = []
    for (var gid in groups) {
      var claimed = false
      for (var k = 0; k < claimedKeys.length; k++)
        if (idMatch(claimedKeys[k], gid)) { claimed = true; break }
      if (claimed) continue

      var entry = entryFor(gid)
      var item = { __running: true, appId: gid }
      if (entry) {
        item.label = String(entry.name || gid)
        item.__entry = entry
      } else {
        item.label = gid
        item.glyph = "󰣆"
      }
      out.push(item)
    }
    return out
  }
}