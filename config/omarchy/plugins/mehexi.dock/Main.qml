import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import qs.Commons

// macOS Tahoe-style dock: a frosted pill on the bottom edge holding the
// pinned apps and then whatever else is running, one dock per monitor.
// Icons magnify and lift under the cursor, running apps carry a dot, and
// right-click opens a small menu (windows, pin, quit).
//
// Config lives in ~/.config/omarchy/dock.json and hot-reloads on save;
// pinning from the context menu writes back to that same file.
Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: (manifest && manifest.id) || "mehexi.dock"
  readonly property string home: Quickshell.env("HOME")

  // ---------------------------------------------------------------- config
  readonly property var defaults: ({
    "pinned": ["chromium", "foot", "nvim", "org.gnome.Nautilus", "localsend", "steam"],
    "iconSize": 44,
    "magnify": 1.3,
    "autohide": false,
    "showOnEmptyWorkspace": true,
    "showBackground": true,
    "bottomMargin": 8,
    "showRunning": true,
    "showLaunchpad": true,
    "monitors": []
  })

  property var cfg: ({})
  // Hyprland latches a layer surface's exclusive zone when the surface is
  // configured, so a panel built before dock.json lands reserves a strip
  // from the DEFAULTS and never gives it back. Hold the windows until the
  // config has been read (or failed to read) once.
  property bool configLoaded: false

  function setting(key) {
    var v = cfg[key]
    return v === undefined || v === null ? defaults[key] : v
  }

  readonly property var pinned: {
    var v = setting("pinned")
    if (!Array.isArray(v)) return []
    var out = []
    for (var i = 0; i < v.length; i++) {
      var s = String(v[i] || "").trim()
      if (s) out.push(s)
    }
    return out
  }
  readonly property int iconSize: Math.max(16, Math.min(128, Number(setting("iconSize")) || 44))
  readonly property real magnify: Math.max(1, Math.min(2, Number(setting("magnify")) || 1))
  readonly property bool autohide: setting("autohide") === true
  // An autohiding dock still stays put when there is nothing to get out of
  // the way of, the way macOS leaves it up on a bare desktop.
  readonly property bool showOnEmptyWorkspace: setting("showOnEmptyWorkspace") !== false
  // With the pill off the icons float free on the wallpaper.
  readonly property bool showBackground: setting("showBackground") !== false
  readonly property bool showRunning: setting("showRunning") !== false
  readonly property bool showLaunchpad: setting("showLaunchpad") !== false
  readonly property var monitors: Array.isArray(setting("monitors")) ? setting("monitors") : []

  // Tile slots are a fixed width, wide enough for a fully magnified icon:
  // the icon scales inside its slot instead of pushing its neighbours
  // sideways. Letting widths grow feeds the new layout back into the
  // cursor hit-test, which makes the magnifier jitter under the pointer.
  readonly property int slot: Math.round(iconSize * Math.max(1.18, magnify))
  readonly property int pad: Style.space(6)
  readonly property int dotRoom: Style.space(7)
  readonly property int dockHeight: iconSize + pad * 2 + dotRoom
  // Gap between the dock and the screen edge. Without the pill there is no
  // rounded corner to float, so this can go to 0 and sit the icons low.
  readonly property int edgeGap: Style.space(Math.max(0, Math.min(60, Number(setting("bottomMargin")))))
  // Padding below the icons inside the strip: the pill needs it, bare icons
  // do not.
  readonly property int innerBottom: showBackground ? pad : Style.space(2)
  // Transparent room above the pill for magnified icons, name labels and the
  // context menu. The input mask keeps it click-through.
  readonly property int headroom: Math.round(iconSize * magnify) + Style.space(260)
  readonly property int sepWidth: Style.space(9)

  readonly property color fg: Color.menu.text
  readonly property string fontFamily: Style.font.family

  FileView {
    id: cfgFile
    path: root.home + "/.config/omarchy/dock.json"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onLoaded: root.applyConfig(text())
    onFileChanged: reload()
    onLoadFailed: {
      root.cfg = ({})
      root.configLoaded = true
    }
  }

  function applyConfig(raw) {
    var next = ({})
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      if (Util.isPlainObject(parsed)) next = parsed
    } catch (e) {
      console.warn("mehexi.dock: dock.json is not valid JSON, keeping defaults")
    }
    cfg = next
    configLoaded = true
    scheduleRebuild()
  }

  // Written back whole, so the file stays a complete and readable document
  // even when it started out missing or partial.
  function saveConfig(mutator) {
    var next = ({})
    for (var k in defaults) next[k] = Util.cloneJson(setting(k))
    mutator(next)
    cfg = next
    cfgFile.setText(JSON.stringify(next, null, 2) + "\n")
    scheduleRebuild()
  }

  // ------------------------------------------------------------- app index
  readonly property var apps: DesktopEntries.applications ? DesktopEntries.applications.values : []
  property var entryIndex: ({})

  function norm(value) {
    return String(value || "").trim().toLowerCase().replace(/\.desktop$/, "")
  }

  // Wayland app ids match the desktop-entry id for most apps, the entry's
  // StartupWMClass for some, and only the tail of a reverse-DNS id for
  // others ("nautilus" against org.gnome.Nautilus). Index all of those, in
  // that order of confidence, so a weaker key never shadows a stronger one.
  function buildIndex() {
    var idx = ({})
    function put(key, entry) {
      var k = root.norm(key)
      if (k && !idx[k]) idx[k] = entry
    }
    var i
    for (i = 0; i < apps.length; i++) if (apps[i] && apps[i].id) put(apps[i].id, apps[i])
    for (i = 0; i < apps.length; i++) if (apps[i] && apps[i].id) put(apps[i].startupClass, apps[i])
    for (i = 0; i < apps.length; i++) {
      if (!apps[i] || !apps[i].id) continue
      var id = norm(apps[i].id)
      var dot = id.lastIndexOf(".")
      if (dot > 0 && dot < id.length - 1) put(id.substr(dot + 1), apps[i])
    }
    for (i = 0; i < apps.length; i++) if (apps[i] && apps[i].id) put(apps[i].name, apps[i])
    entryIndex = idx
  }

  function entryFor(key) {
    return entryIndex[norm(key)] || null
  }

  function iconFor(icon) {
    var v = String(icon || "")
    if (v === "") return Quickshell.iconPath("application-x-executable", true)
    if (v.indexOf("file://") === 0 || v.indexOf("image://") === 0) return v
    if (v.charAt(0) === "/") return Util.fileUrl(v)
    var themed = Quickshell.iconPath(v, true)
    return themed !== "" ? themed : Quickshell.iconPath("application-x-executable", true)
  }

  // ------------------------------------------------------------ live state
  readonly property var toplevels: ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []

  // Which app owns the focused window. Read live by the tiles rather than
  // baked into the model, so focus changes don't rebuild anything.
  readonly property string activeKey: {
    var t = ToplevelManager.activeToplevel
    if (!t) return ""
    var e = entryFor(t.appId)
    return e ? norm(e.id) : norm(t.appId)
  }

  property var model: []
  property var bouncing: ({})

  function groupsByKey() {
    var groups = ({})
    var order = []
    for (var i = 0; i < toplevels.length; i++) {
      var t = toplevels[i]
      if (!t) continue
      var e = entryFor(t.appId)
      var key = e ? norm(e.id) : norm(t.appId)
      if (!key) continue
      if (!groups[key]) {
        groups[key] = { key: key, entry: e, appId: String(t.appId || ""), windows: [] }
        order.push(key)
      }
      groups[key].windows.push(t)
    }
    return { map: groups, order: order }
  }

  function rebuild() {
    var running = groupsByKey()
    var out = []
    var seen = ({})

    if (showLaunchpad) out.push({ kind: "launchpad", key: "__launchpad", name: "Applications", windows: [] })

    for (var i = 0; i < pinned.length; i++) {
      var raw = pinned[i]
      var entry = entryFor(raw)
      var key = entry ? norm(entry.id) : norm(raw)
      if (!key || seen[key]) continue
      seen[key] = true
      var group = running.map[key]
      out.push({
        kind: "app",
        key: key,
        pinKey: entry ? String(entry.id) : raw,
        name: entry ? String(entry.name || entry.id) : raw,
        icon: iconFor(entry ? entry.icon : ""),
        desktopId: entry ? String(entry.id) : "",
        pinned: true,
        windows: group ? group.windows : []
      })
    }

    if (showRunning) {
      var extras = []
      for (var r = 0; r < running.order.length; r++) {
        var k = running.order[r]
        if (seen[k]) continue
        seen[k] = true
        var g = running.map[k]
        extras.push({
          kind: "app",
          key: k,
          pinKey: g.entry ? String(g.entry.id) : g.appId,
          name: g.entry ? String(g.entry.name || g.entry.id) : (g.appId || k),
          icon: iconFor(g.entry ? g.entry.icon : ""),
          desktopId: g.entry ? String(g.entry.id) : "",
          pinned: false,
          windows: g.windows
        })
      }
      if (extras.length > 0) {
        if (out.length > 0) out.push({ kind: "sep", key: "__sep", windows: [] })
        out = out.concat(extras)
      }
    }

    model = out
  }

  function scheduleRebuild() {
    rebuildTimer.restart()
  }

  Timer {
    id: rebuildTimer
    interval: 16
    onTriggered: root.rebuild()
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      root.buildIndex()
      root.scheduleRebuild()
    }
  }

  // Windows come and go, and some apps set their app id a beat after
  // mapping, so watch each toplevel and not just the list.
  Instantiator {
    model: ToplevelManager.toplevels
    onObjectAdded: function(index, object) { root.scheduleRebuild() }
    onObjectRemoved: function(index, object) { root.scheduleRebuild() }

    delegate: QtObject {
      required property var modelData
      readonly property var watcher: Connections {
        target: modelData
        function onAppIdChanged() { root.scheduleRebuild() }
      }
    }
  }

  Component.onCompleted: {
    buildIndex()
    rebuild()
  }

  // --------------------------------------------------------------- actions
  function launch(item) {
    if (!item || !item.desktopId) return
    startBounce(item.key)
    // Same launch path as Omarchy's launcher: a scope under app-graphical.slice.
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(item.desktopId + ".desktop"))
  }

  // Click a running app to focus it; click again to step through its windows.
  function activate(item) {
    var wins = (item && item.windows) || []
    if (wins.length === 0) {
      launch(item)
      return
    }
    var at = -1
    for (var i = 0; i < wins.length; i++) if (wins[i] && wins[i].activated) { at = i; break }
    var next = at === -1 ? wins[0] : wins[(at + 1) % wins.length]
    if (next) next.activate()
  }

  function quit(item) {
    var wins = (item && item.windows) || []
    for (var i = 0; i < wins.length; i++) if (wins[i]) wins[i].close()
  }

  function setPinned(item, want) {
    if (!item || !item.pinKey) return
    saveConfig(function(next) {
      var list = Array.isArray(next.pinned) ? next.pinned.slice() : []
      var kept = []
      for (var i = 0; i < list.length; i++)
        if (root.norm(list[i]) !== item.key) kept.push(list[i])
      if (want) kept.push(item.pinKey)
      next.pinned = kept
    })
  }

  function toggleLaunchpad() {
    // A plugin may only summon itself through the shell API, so go through
    // the same CLI the SUPER+SPACE binding uses.
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "mehexi.launchpad", "{}"])
  }

  // A launching app bounces until its first window shows up, or we give up.
  function startBounce(key) {
    var next = ({})
    for (var k in bouncing) next[k] = bouncing[k]
    next[key] = true
    bouncing = next
    bounceTimeout.restart()
  }

  function stopBounce(key) {
    if (!bouncing[key]) return
    var next = ({})
    for (var k in bouncing) if (k !== key) next[k] = bouncing[k]
    bouncing = next
  }

  Timer {
    id: bounceTimeout
    interval: 10000
    onTriggered: root.bouncing = ({})
  }

  // -------------------------------------------------------------- the dock
  Variants {
    model: root.configLoaded ? Quickshell.screens : []

    delegate: Component {
      DockPanel {
        required property var modelData

        screen: modelData
        dockScreen: modelData
      }
    }
  }

  component CtxRow: Rectangle {
    id: ctxRow

    property real rowWidth: 0
    property int rowHeight: Style.space(26)
  property string label: ""
    property bool dim: false
    property bool active: true
    signal triggered()

    width: ctxRow.rowWidth
    height: visible ? ctxRow.rowHeight : 0
    radius: Style.space(8)
    color: ctxRowHover.hovered && ctxRow.active
      ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10) : "transparent"

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      text: ctxRow.label
      color: root.fg
      opacity: !ctxRow.active ? 0.35 : (ctxRow.dim ? 0.7 : 1)
      elide: Text.ElideRight
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    HoverHandler {
      id: ctxRowHover
      cursorShape: Qt.PointingHandCursor
    }

    MouseArea {
      anchors.fill: parent
      enabled: ctxRow.active
      onClicked: ctxRow.triggered()
    }
  }

  component DockPanel: PanelWindow {
    id: win

    required property var dockScreen
    readonly property string screenName: dockScreen && dockScreen.name ? String(dockScreen.name) : ""
    readonly property bool onThisScreen: root.monitors.length === 0
      || root.monitors.indexOf(screenName) !== -1

    visible: onThisScreen && root.model.length > 0
    color: "transparent"
    WlrLayershell.namespace: "mehexi-dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Reserve the strip unless the dock hides itself; an autohiding dock
    // floats over the windows instead.
    exclusionMode: root.autohide ? ExclusionMode.Ignore : ExclusionMode.Normal
    exclusiveZone: root.autohide ? 0 : root.dockHeight + root.edgeGap

    anchors {
      bottom: true
      left: true
      right: true
    }

    implicitHeight: root.dockHeight + root.edgeGap + root.headroom

    // Context-menu state is per screen: only the dock that was clicked
    // opens one.
    property var ctxItem: null
    property real ctxAnchorX: 0
    readonly property bool ctxOpen: ctxItem !== null

    // The workspace on show on this dock's monitor. Prefer the focused
    // workspace (what the bar's own widget reads, so it is always live) and
    // fall back to scanning for this monitor's active one on a second screen.
    readonly property var hyprWorkspace: {
      var fw = Hyprland.focusedWorkspace
      if (fw && (!fw.monitor || String(fw.monitor.name) === win.screenName)) return fw
      var wss = Hyprland.workspaces ? Hyprland.workspaces.values : []
      for (var i = 0; i < wss.length; i++) {
        var w = wss[i]
        if (w && w.active && w.monitor && String(w.monitor.name) === win.screenName) return w
      }
      return null
    }
    readonly property bool workspaceEmpty: !!hyprWorkspace && !!hyprWorkspace.toplevels
      && hyprWorkspace.toplevels.values.length === 0

    property bool pointerInside: false
    readonly property bool revealed: !root.autohide || pointerInside || ctxOpen
      || (root.showOnEmptyWorkspace && workspaceEmpty)
    property real reveal: revealed ? 1 : 0
    Behavior on reveal {
      NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }

    // Rest geometry of the visible pill, in window coordinates.
    readonly property int stripX: Math.round((win.width - strip.width) / 2)
    readonly property int stripY: win.height - root.edgeGap - root.dockHeight

    // Everything outside the pill is click-through. While hidden, only a
    // sliver on the screen edge stays live so the dock can be summoned
    // back; while a context menu is open the whole surface takes clicks, so
    // one click anywhere dismisses it.
    mask: Region {
      x: win.ctxOpen ? 0 : (win.revealed ? win.stripX : 0)
      y: win.ctxOpen ? 0 : (win.revealed ? win.stripY : win.height - Style.space(5))
      width: win.ctxOpen ? win.width : (win.revealed ? strip.width : win.width)
      height: win.ctxOpen ? win.height
        : (win.revealed ? root.dockHeight + root.edgeGap : Style.space(5))
    }

    // Edge sliver that brings an autohidden dock back.
    Item {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Style.space(5)
      visible: root.autohide

      HoverHandler {
        id: edgeHover
        onHoveredChanged: if (hovered) win.pointerInside = true
      }
    }

    // Dismiss the context menu on any click outside it.
    MouseArea {
      anchors.fill: parent
      visible: win.ctxOpen
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onPressed: win.ctxItem = null
    }

    // ------------------------------------------------------------ the pill
    Item {
      id: strip
      width: content.implicitWidth + root.pad * 2
      height: root.dockHeight
      x: win.stripX
      y: win.stripY
      transform: Translate {
        y: (1 - win.reveal) * (root.dockHeight + root.edgeGap)
      }

      HoverHandler {
        id: stripHover
        onHoveredChanged: {
          if (hovered) win.pointerInside = true
          else if (!win.ctxOpen) leaveTimer.restart()
        }
      }

      // Don't snap away the moment the cursor crosses the seam between the
      // pill and the edge sliver.
      Timer {
        id: leaveTimer
        interval: 220
        onTriggered: if (!stripHover.hovered && !edgeHover.hovered) win.pointerInside = false
      }

      // Frosted glass: Hyprland blurs everything under this layer above
      // alpha 0.3 (see the mehexi-dock layer rule in hyprland.lua), so the
      // tint has to stay above that threshold to keep icons readable.
      ClippingRectangle {
        id: glass
        anchors.fill: parent
        visible: root.showBackground
        radius: Math.round(root.dockHeight * 0.34)
        color: "transparent"

        Rectangle {
          anchors.fill: parent
          color: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 0.5)
        }

        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.08) }
            GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.0) }
          }
        }
      }

      Rectangle {
        anchors.fill: parent
        visible: root.showBackground
        radius: glass.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
      }

      // Cursor position across the whole row drives the magnifier. A
      // HoverHandler reports it without intercepting the tiles' clicks.
      HoverHandler { id: rowHover }

      readonly property real hoverX: rowHover.point.position.x
      readonly property bool magnifying: rowHover.hovered && root.magnify > 1.001

      // Smooth cosine falloff either side of the cursor, measured against
      // the tiles' fixed slot centres.
      function scaleAt(centerX) {
        if (!magnifying) return 1
        var d = Math.abs(hoverX - centerX) / (root.slot * 1.9)
        if (d >= 1) return 1
        var f = Math.cos(d * Math.PI / 2)
        return 1 + (root.magnify - 1) * f * f
      }

      Row {
        id: content
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        height: parent.height

        Repeater {
          model: root.model

          delegate: Item {
            id: tile

            required property var modelData
            required property int index

            readonly property bool isSep: modelData.kind === "sep"
            readonly property bool isLaunchpad: modelData.kind === "launchpad"
            readonly property var windows: modelData.windows || []
            readonly property bool running: windows.length > 0
            readonly property bool active: !isSep && !isLaunchpad && root.activeKey === modelData.key
            readonly property string label: String(modelData.name || "")

            width: isSep ? root.sepWidth : root.slot
            height: content.height

            // Slot centre within the pill — fixed, which is what keeps the
            // magnifier from chasing its own layout.
            readonly property real centerX: content.x + x + width / 2

            property real zoom: isSep ? 1 : strip.scaleAt(centerX)
            readonly property real iconPx: root.iconSize * zoom

            Behavior on zoom {
              NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
            }

            // Bounce while an app we launched hasn't shown a window yet.
            property real bounce: 0
            readonly property bool pending: !isSep && !isLaunchpad
              && root.bouncing[modelData.key] === true

            onRunningChanged: if (running) root.stopBounce(modelData.key)
            onPendingChanged: {
              if (pending) bounceAnim.restart()
              else { bounceAnim.stop(); bounce = 0 }
            }

            SequentialAnimation {
              id: bounceAnim
              loops: Animation.Infinite
              NumberAnimation { target: tile; property: "bounce"; to: Style.space(14); duration: 320; easing.type: Easing.OutQuad }
              NumberAnimation { target: tile; property: "bounce"; to: 0; duration: 360; easing.type: Easing.OutBounce }
              PauseAnimation { duration: 240 }
            }

            // ----- separator between pinned and merely running apps
            Rectangle {
              visible: tile.isSep
              anchors.centerIn: parent
              width: 1
              height: Math.round(root.iconSize * 0.58)
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.22)
            }

            HoverHandler {
              id: tileHover
              enabled: !tile.isSep
              cursorShape: Qt.PointingHandCursor
            }

            // Whole-pixel geometry: a half-pixel offset (an odd slot minus an
            // odd icon, halved) is enough to make every icon render soft.
            Item {
              id: iconSlot
              visible: !tile.isSep
              width: Math.round(tile.iconPx)
              height: width
              x: Math.round((tile.width - width) / 2)
              anchors.bottom: parent.bottom
              anchors.bottomMargin: root.innerBottom + root.dotRoom
                + Math.round((tile.zoom - 1) * root.iconSize * 0.18)
              transform: Translate { y: -tile.bounce }

              Image {
                id: iconImage
                anchors.fill: parent
                visible: !tile.isLaunchpad
                source: tile.isLaunchpad ? "" : (modelData.icon || "")
                // Rasterise once at the fully magnified size. Mipmaps blend
                // down to a smaller level as the icon grows, which is what
                // made magnified icons look mushy; plain bilinear off a
                // correctly sized raster stays sharp at both ends.
                sourceSize.width: Math.round(root.iconSize * root.magnify)
                sourceSize.height: Math.round(root.iconSize * root.magnify)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: false
                scale: tileArea.pressed ? 0.88 : 1
                Behavior on scale { SpringAnimation { spring: 5; damping: 0.3; epsilon: 0.002 } }
              }

              // The Launchpad button gets a glyph plate instead of an app
              // icon, matching the tool tiles inside mehexi.launchpad.
              Rectangle {
                anchors.fill: parent
                visible: tile.isLaunchpad
                radius: Math.round(width * 0.26)
                // Without the pill behind it this plate has to read as an
                // icon in its own right, so it gets a solid scrim instead of
                // a faint wash of the foreground.
                color: root.showBackground
                  ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.13)
                  : Qt.rgba(Color.menu.background.r, Color.menu.background.g,
                            Color.menu.background.b, 0.72)
                border.width: 1
                border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b,
                  root.showBackground ? 0.10 : 0.22)
                scale: iconImage.scale

                Text {
                  anchors.centerIn: parent
                  text: "󰀻"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Math.round(parent.width * 0.5)
                }
              }
            }

            // Running dot.
            Rectangle {
              width: Style.space(4)
              height: width
              radius: width / 2
              x: Math.round((parent.width - width) / 2)
              anchors.bottom: parent.bottom
              anchors.bottomMargin: root.innerBottom
              visible: tile.running && !tile.isSep
              color: tile.active ? Color.accent
                : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.showBackground ? 0.55 : 0.9)
              Behavior on color { ColorAnimation { duration: 160 } }
            }

            // Name above the icon, like macOS. Parented to the pill so it
            // can overflow past this tile's bounds.
            Rectangle {
              id: tooltip
              parent: strip
              z: 5
              visible: tileHover.hovered && !win.ctxOpen && tile.label !== ""
              width: tooltipText.implicitWidth + Style.space(18)
              height: tooltipText.implicitHeight + Style.space(10)
              x: Math.round(Math.max(Style.space(4),
                 Math.min(strip.width - width - Style.space(4), tile.centerX - width / 2)))
              y: -height - Style.space(8)
              radius: Math.round(height / 2)
              color: Qt.rgba(Color.tooltip.background.r, Color.tooltip.background.g, Color.tooltip.background.b, 0.92)
              border.width: 1
              border.color: Qt.rgba(1, 1, 1, 0.12)

              Text {
                id: tooltipText
                anchors.centerIn: parent
                text: tile.label
                color: Color.tooltip.text
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            MouseArea {
              id: tileArea
              anchors.fill: parent
              enabled: !tile.isSep
              acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

              onClicked: function(mouse) {
                if (tile.isLaunchpad) {
                  if (mouse.button === Qt.LeftButton) root.toggleLaunchpad()
                  return
                }
                if (mouse.button === Qt.RightButton) {
                  win.ctxAnchorX = tile.centerX
                  win.ctxItem = tile.modelData
                } else if (mouse.button === Qt.MiddleButton) {
                  root.launch(tile.modelData)
                } else {
                  root.activate(tile.modelData)
                }
              }
            }
          }
        }
      }
    }

    // -------------------------------------------------------- context menu
    Rectangle {
      id: ctxCard

      readonly property var item: win.ctxItem
      readonly property var windows: (item && item.windows) || []
      readonly property int rowH: Style.space(26)

      visible: win.ctxOpen
      z: 10
      width: Style.space(230)
      height: menuColumn.implicitHeight + Style.space(12)
      x: Math.round(Math.max(Style.space(8),
         Math.min(win.width - width - Style.space(8), strip.x + win.ctxAnchorX - width / 2)))
      y: Math.round(Math.max(Style.space(6), strip.y - height - Style.space(10)))
      radius: Style.space(14)
      color: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 0.97)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.14)

      Column {
        id: menuColumn
        anchors.centerIn: parent
        width: parent.width - Style.space(12)

        // The app's windows, by title; clicking one focuses that window.
        Repeater {
          model: ctxCard.windows.length > 1 ? ctxCard.windows.slice(0, 6) : []

          delegate: CtxRow {
            required property var modelData
            rowWidth: menuColumn.width
            rowHeight: ctxCard.rowH
            label: String(modelData.title || modelData.appId || "Window")
            dim: true
            onTriggered: {
              modelData.activate()
              win.ctxItem = null
            }
          }
        }

        Rectangle {
          visible: ctxCard.windows.length > 1
          width: parent.width
          height: 1
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
        }

        CtxRow {
          rowWidth: menuColumn.width
          rowHeight: ctxCard.rowH
          label: ctxCard.windows.length > 0 ? "New Window" : "Open"
          active: !!ctxCard.item && ctxCard.item.desktopId !== ""
          onTriggered: {
            var target = ctxCard.item
            win.ctxItem = null
            root.launch(target)
          }
        }

        CtxRow {
          rowWidth: menuColumn.width
          rowHeight: ctxCard.rowH
          label: (ctxCard.item && ctxCard.item.pinned) ? "Remove from Dock" : "Keep in Dock"
          onTriggered: {
            var target = ctxCard.item
            win.ctxItem = null
            root.setPinned(target, !(target && target.pinned))
          }
        }

        CtxRow {
          rowWidth: menuColumn.width
          rowHeight: ctxCard.rowH
          label: "Quit"
          visible: ctxCard.windows.length > 0
          onTriggered: {
            var target = ctxCard.item
            win.ctxItem = null
            root.quit(target)
          }
        }
      }
    }
  }
}
