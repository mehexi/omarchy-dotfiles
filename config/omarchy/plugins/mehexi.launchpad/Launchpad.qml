import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import qs.Commons
import qs.Ui

// macOS Tahoe-style "Applications" panel: a compact frosted card over the
// desktop with the search field as its title, category chips, a row of
// recently used apps, and a scrolling five-column grid of everything else.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  readonly property string pluginId: (manifest && manifest.id) || "mehexi.launchpad"

  // Apps come straight from DesktopEntries (the same source Omarchy's
  // launcher uses); the sandboxed shell API doesn't hand us its app library.
  readonly property var apps: DesktopEntries.applications ? DesktopEntries.applications.values : []
  property var hidden: ({})

  property bool opened: false
  property real reveal: 0
  property string query: ""
  property string category: ""
  property var model: []
  property var suggestions: []
  property var categories: []
  property int selected: 0
  property bool keyboardNav: false
  property var recent: []
  property int openSerial: 0

  readonly property color fg: Color.menu.text
  readonly property color accent: Color.accent
  readonly property string fontFamily: Style.font.family
  readonly property int columns: 7
  readonly property int cellW: Style.space(80)
  readonly property int cellH: Style.space(76)
  readonly property int iconSize: Style.space(38)
  readonly property int pad: Style.space(18)
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/mehexi-launchpad"

  // Category → chip. First matching group wins, so the order resolves apps
  // that list several categories (Neovim is Utility + Development).
  readonly property var groups: [
    { title: "Games", cats: ["Game"] },
    { title: "Developer", cats: ["Development", "IDE"] },
    { title: "Productivity", cats: ["Office", "Calendar", "Finance", "Education", "ProjectManagement", "WordProcessor", "Spreadsheet", "Presentation"] },
    { title: "Creativity", cats: ["Graphics", "AudioVideo", "Audio", "Video", "Photography", "2DGraphics", "3DGraphics"] },
    { title: "Social", cats: ["Network", "WebBrowser", "Email", "Chat", "InstantMessaging"] },
    { title: "Utilities", cats: ["Utility", "Accessories", "FileManager", "TerminalEmulator", "TextEditor", "System", "Settings", "Monitor"] }
  ]

  // Omarchy menu sections (everything on the old SUPER+SPACE menu except
  // Apps, which this launcher replaces). Icons copied from omarchy-menu.jsonc.
  readonly property var menuSections: [
    { route: "learn", icon: "󰧑", label: "Learn" },
    { route: "trigger", icon: "󱓞", label: "Trigger" },
    { route: "style", icon: "", label: "Style" },
    { route: "setup", icon: "", label: "Setup" },
    { route: "install", icon: "󰉉", label: "Install" },
    { route: "remove", icon: "󰭌", label: "Remove" },
    { route: "update", icon: "", label: "Update" },
    { route: "about", icon: "", label: "About" },
    { route: "system", icon: "", label: "System" },
    { route: "vpn", icon: "", label: "VPN" }
  ]

  function openSection(route) {
    dismiss()
    var cmd = route === "about" ? "omarchy-launch-about" : "omarchy menu summon " + route
    Quickshell.execDetached(["bash", "-c", "sleep 0.2; " + cmd])
  }

  // ---------------- lifecycle ----------------
  function open(payloadJson) {
    if (opened) return
    opened = true
    searchInput.text = ""
    query = ""
    category = ""
    selected = 0
    keyboardNav = false
    openSerial++
    if (!hiddenProc.running) hiddenProc.running = true
    rebuild()
    grid.positionViewAtBeginning()
    closeAnim.stop()
    openAnim.restart()
    Qt.callLater(function() { searchInput.forceActiveFocus() })
  }

  function close() {
    if (!opened) return
    opened = false
    openAnim.stop()
    closeAnim.restart()
  }

  function dismiss() {
    close()
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
  }

  function toggle() { opened ? dismiss() : open("{}") }

  // ---------------- data ----------------
  function groupFor(entry) {
    var cats = []
    try { cats = entry.categories ? Array.prototype.slice.call(entry.categories) : [] } catch (e) { cats = [] }
    for (var g = 0; g < groups.length; g++)
      for (var c = 0; c < cats.length; c++)
        if (groups[g].cats.indexOf(String(cats[c])) !== -1) return groups[g].title
    return "Other"
  }

  function iconFor(icon) {
    var v = String(icon || "")
    if (v === "") return Quickshell.iconPath("application-x-executable", true)
    if (v.indexOf("file://") === 0 || v.indexOf("image://") === 0) return v
    if (v.charAt(0) === "/") return "file://" + v
    var themed = Quickshell.iconPath(v, true)
    return themed !== "" ? themed : Quickshell.iconPath("application-x-executable", true)
  }

  // Name prefix beats word prefix beats substring; generic name and
  // keywords count a little less than the name.
  function score(entry, q) {
    var name = String(entry.name || "").toLowerCase()
    if (name.indexOf(q) === 0) return 100
    var words = name.split(/[^a-z0-9]+/)
    for (var i = 0; i < words.length; i++) if (words[i].indexOf(q) === 0) return 80
    if (name.indexOf(q) !== -1) return 60
    var extra = [entry.genericName, entry.comment, entry.id].join(" ").toLowerCase()
    try { if (entry.keywords) extra += " " + Array.prototype.slice.call(entry.keywords).join(" ").toLowerCase() } catch (e) { }
    return extra.indexOf(q) !== -1 ? 30 : 0
  }

  function rebuild() {
    var seen = {}
    var all = []
    for (var i = 0; i < apps.length; i++) {
      var e = apps[i]
      if (!e || !e.id || e.noDisplay || seen[e.id] || hidden[e.id]) continue
      seen[e.id] = true
      all.push({ id: String(e.id), name: String(e.name || e.id), icon: iconFor(e.icon), group: groupFor(e), entry: e })
    }
    all.sort(function(a, b) { return a.name.toLowerCase().localeCompare(b.name.toLowerCase()) })

    // Chips only for groups that actually have apps.
    var present = {}
    for (var p = 0; p < all.length; p++) present[all[p].group] = true
    var chips = []
    for (var g = 0; g < groups.length; g++) if (present[groups[g].title]) chips.push(groups[g].title)
    if (present["Other"]) chips.push("Other")
    categories = chips

    var byId = {}
    for (var b = 0; b < all.length; b++) byId[all[b].id] = all[b]
    var sugg = []
    for (var r = 0; r < recent.length && sugg.length < columns; r++)
      if (byId[recent[r]]) sugg.push(byId[recent[r]])
    suggestions = sugg

    var out = all
    if (category !== "") out = out.filter(function(a) { return a.group === category })
    if (query !== "") {
      var q = query.toLowerCase().trim()
      out = out.map(function(a) { return { a: a, s: score(a.entry, q) } })
        .filter(function(x) { return x.s > 0 })
        .sort(function(x, y) { return y.s - x.s })
        .map(function(x) { return x.a })
    }
    model = out.map(function(a) { return { id: a.id, name: a.name, icon: a.icon } })
    if (selected >= model.length) selected = Math.max(0, model.length - 1)
  }

  function launch(app) {
    if (!app) return
    var next = [app.id].concat(recent.filter(function(id) { return id !== app.id })).slice(0, 20)
    recent = next
    recentFile.setText(JSON.stringify(next))
    // Same launch path as Omarchy's launcher: a scope under app-graphical.slice.
    Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", app.id + ".desktop"])
    dismiss()
  }

  function setCategory(c) {
    category = category === c ? "" : c
    selected = 0
    rebuild()
    grid.positionViewAtBeginning()
  }

  function move(delta) {
    if (!model.length) return
    if (!keyboardNav) { keyboardNav = true; selected = 0; return }
    var next = selected + delta
    if (next < 0 || next >= model.length) return
    selected = next
    grid.positionViewAtIndex(selected, GridView.Contain)
  }

  // ---------------- state ----------------
  Process {
    running: true
    command: ["mkdir", "-p", root.stateDir]
  }

  FileView {
    id: recentFile
    path: root.stateDir + "/recent.json"
    printErrors: false
    onLoaded: {
      try { root.recent = JSON.parse(text()) || [] } catch (e) { root.recent = [] }
    }
  }

  // Same hide rules as Omarchy's launcher: its hides file plus entries
  // hidden for this desktop.
  Process {
    id: hiddenProc
    running: true
    command: ["bash", "-c",
      "cat \"$OMARCHY_PATH/default/omarchy/launcher.hides\" 2>/dev/null; " +
      "\"$OMARCHY_PATH/shell/services/hidden-entries.sh\" \"$XDG_CURRENT_DESKTOP\" 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = {}
        String(text || "").split("\n").forEach(function(line) {
          var id = line.trim().replace(/\.desktop$/, "")
          if (id) next[id] = true
        })
        root.hidden = next
        if (root.opened) root.rebuild()
      }
    }
  }

  // ---------------- animation ----------------
  NumberAnimation {
    id: openAnim
    target: root; property: "reveal"; to: 1
    duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.9
  }
  NumberAnimation {
    id: closeAnim
    target: root; property: "reveal"; to: 0
    duration: 150; easing.type: Easing.InCubic
  }

  // ---------------- window ----------------
  PanelWindow {
    id: win
    visible: root.opened || root.reveal > 0.001
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "mehexi-launchpad"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Very light dim, like Spotlight: the desktop stays visible.
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.18 * Math.min(1, root.reveal))
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      id: card
      width: root.columns * root.cellW + root.pad * 2
      height: Math.min(Style.space(560), win.height - Style.space(100))
      x: Math.round((win.width - width) / 2)
      y: Math.round((win.height - height) / 2 - win.height * 0.04)

      opacity: Math.min(1, root.reveal * 1.4)
      scale: 0.9 + 0.1 * root.reveal
      transform: Translate { y: (1 - Math.min(1, root.reveal)) * Style.space(16) }

      MouseArea { anchors.fill: parent; onClicked: {} }

      // ----- frosted glass: real Hyprland blur of whatever is behind -----
      ClippingRectangle {
        id: glass
        anchors.fill: parent
        radius: Style.space(26)
        color: "transparent"

        // Tint so text stays readable on any wallpaper.
        Rectangle {
          anchors.fill: parent
          // Hyprland blurs everything under this layer above alpha 0.3
          // (see the mehexi-launchpad layer rule), so the tint must stay above it.
          color: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 0.5)
        }

        // Soft top sheen.
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.07) }
            GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.0) }
          }
        }
      }

      Rectangle {
        anchors.fill: parent
        radius: glass.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
      }

      // ----- header: icon + search as the title -----
      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Style.space(14)
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        height: Style.space(40)

        Text {
          id: headerIcon
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "󰀻"
          color: root.fg
          opacity: 0.75
          font.family: root.fontFamily
          font.pixelSize: Style.font.displayLarge * 0.8
        }

        TextInput {
          id: searchInput
          anchors.left: headerIcon.right
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          color: root.fg
          selectionColor: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.display * 0.85
          clip: true
          onTextChanged: {
            root.query = text
            root.selected = 0
            root.keyboardNav = text !== ""
            root.rebuild()
            grid.positionViewAtBeginning()
          }

          Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: searchInput.text === ""
            text: "Applications"
            color: root.fg
            opacity: 0.55
            font: searchInput.font
          }

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            switch (event.key) {
            case Qt.Key_Escape:
              if (searchInput.text !== "") searchInput.text = ""
              else root.dismiss()
              break
            case Qt.Key_Return:
            case Qt.Key_Enter:
              if (root.model.length) root.launch(root.model[root.keyboardNav ? root.selected : 0])
              break
            case Qt.Key_Left:
              if (!root.keyboardNav) return
              root.move(-1); break
            case Qt.Key_Right:
              if (!root.keyboardNav) return
              root.move(1); break
            case Qt.Key_Up: root.move(-root.columns); break
            case Qt.Key_Down: root.move(root.keyboardNav ? root.columns : 0); break
            case Qt.Key_Tab: root.move(1); break
            case Qt.Key_Backtab: root.move(-1); break
            default: return
            }
            event.accepted = true
          }
        }
      }

      // ----- Omarchy tools (the old SUPER+SPACE menu), styled like apps -----
      Flow {
        id: tools
        readonly property var items: root.query === "" ? root.menuSections
          : root.menuSections.filter(function(t) { return t.label.toLowerCase().indexOf(root.query.toLowerCase().trim()) !== -1 })
        anchors.top: header.bottom
        anchors.topMargin: Style.space(8)
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.columns * root.cellW
        height: items.length ? implicitHeight : 0
        visible: items.length > 0

        Repeater {
          model: tools.items
          delegate: AppTile {
            required property var modelData
            required property int index
            app: modelData
            order: index
            current: false
          }
        }
      }

      Rectangle {
        id: toolsSepLine
        anchors.top: tools.bottom
        anchors.topMargin: tools.visible ? Style.space(6) : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.pad + Style.space(6)
        anchors.rightMargin: root.pad + Style.space(6)
        height: 1
        visible: tools.visible
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
      }

      // ----- recently opened -----
      Item {
        id: recentBlock
        readonly property bool shown: root.query === "" && root.suggestions.length > 0
        anchors.top: toolsSepLine.bottom
        anchors.topMargin: shown ? Style.space(8) : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        height: shown ? recentLabel.height + Style.space(4) + root.cellH + Style.space(8) : 0
        visible: shown

        Text {
          id: recentLabel
          leftPadding: Style.space(6)
          text: "Recently Opened"
          color: root.fg
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Row {
          anchors.top: recentLabel.bottom
          anchors.topMargin: Style.space(4)
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.columns * root.cellW

          Repeater {
            model: recentBlock.shown ? root.suggestions : []
            delegate: AppTile {
              required property var modelData
              required property int index
              app: modelData
              order: index + tools.items.length
              current: false
            }
          }
        }

        Rectangle {
          anchors.bottom: parent.bottom
          anchors.leftMargin: Style.space(6)
          anchors.rightMargin: Style.space(6)
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
        }
      }

      Item { id: toolsSep; anchors.top: recentBlock.visible ? recentBlock.bottom : toolsSepLine.bottom; height: 0; width: 1 }

      // ----- all apps -----
      GridView {
        id: grid
        anchors.top: toolsSep.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        anchors.bottomMargin: Style.space(10)
        clip: true
        model: root.model
        cellWidth: root.cellW
        cellHeight: root.cellH
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 2600
        highlightFollowsCurrentItem: false

        delegate: AppTile {
          required property var modelData
          required property int index
          app: modelData
          order: index + tools.items.length + (recentBlock.shown ? root.suggestions.length : 0)
          current: root.keyboardNav && root.selected === index
        }
      }

      Text {
        anchors.centerIn: grid
        visible: root.model.length === 0
        text: root.query ? "No apps match “" + root.query + "”" : "No apps"
        color: root.fg
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }

  // ---------------- tile ----------------
  component AppTile: Item {
    id: tile
    property var app: ({})
    property int order: 0
    property bool current: false
    property real appear: 0

    width: root.cellW
    height: root.cellH

    // Staggered entrance each time the panel opens: tiles rise and fade in.
    function play() {
      appear = 0
      appearAnim.restart()
    }
    Component.onCompleted: play()
    Connections {
      target: root
      function onOpenSerialChanged() { tile.play() }
    }

    SequentialAnimation {
      id: appearAnim
      PauseAnimation { duration: root.query !== "" ? 0 : 90 + Math.min(tile.order * 18, 360) }
      NumberAnimation { target: tile; property: "appear"; to: 1; duration: 320; easing.type: Easing.OutCubic }
    }

    opacity: appear
    transform: Translate { y: (1 - tile.appear) * Style.space(10) }

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.space(3)
      radius: Style.space(14)
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, tile.current ? 0.14 : (hover.hovered ? 0.07 : 0))
      Behavior on color { ColorAnimation { duration: 140 } }
    }

    readonly property bool isTool: !!tile.app.route

    Image {
      id: icon
      visible: !tile.isTool
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Style.space(8)
      width: root.iconSize
      height: root.iconSize
      source: tile.isTool ? "" : (tile.app.icon || "")
      sourceSize.width: root.iconSize * 2
      sourceSize.height: root.iconSize * 2
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true

      // macOS lift on hover, squish on press.
      scale: area.pressed ? 0.86 : ((hover.hovered || tile.current) ? 1.1 : 1)
      Behavior on scale { SpringAnimation { spring: 5; damping: 0.3; epsilon: 0.002 } }
    }

    Rectangle {
      id: toolIcon
      visible: tile.isTool
      anchors.fill: icon
      radius: Style.space(11)
      scale: icon.scale
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.13)
      border.width: 1
      border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)

      Text {
        anchors.centerIn: parent
        text: tile.app.icon || ""
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Math.round(root.iconSize * 0.48)
      }
    }

    Text {
      anchors.top: icon.bottom
      anchors.topMargin: Style.space(6)
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width - Style.space(6)
      horizontalAlignment: Text.AlignHCenter
      text: tile.app.name || tile.app.label || ""
      elide: Text.ElideRight
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }

    MouseArea {
      id: area
      anchors.fill: parent
      onClicked: tile.isTool ? root.openSection(tile.app.route) : root.launch(tile.app)
    }
  }
}
