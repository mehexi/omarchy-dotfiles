import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

// macOS-style control center. The bar shows the profile picture; clicking it
// opens a card of toggles, media, sliders and quick actions. Clicking a
// tile's round icon toggles it, clicking the rest of the tile opens the
// matching built-in Omarchy panel (kept loaded but hidden on the bar).
Panel {
  id: root
  moduleName: "mehexi.control-center"
  ipcTarget: "mehexi.control-center"

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color contrast: Color.background
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property real gap: Style.space(10)

  readonly property string avatarPath: {
    var p = String(setting("avatar", "~/.face") || "")
    if (p.indexOf("~/") === 0) p = Quickshell.env("HOME") + p.slice(1)
    return p
  }
  readonly property string userName: String(setting("name", "") || Quickshell.env("USER") || "user")

  // ---------- toggles ----------
  // Third-party plugins can't reach Omarchy's first-party services, so these
  // go through the same CLI the keybindings use and read state back.
  property bool dndOn: false
  property bool nightOn: false
  property bool awakeOn: false

  function toggleState(kind, cmd) {
    if (kind === "dnd") dndOn = !dndOn
    else if (kind === "night") nightOn = !nightOn
    else if (kind === "awake") awakeOn = !awakeOn
    run(["bash", "-c", cmd])
    stateRefresh.restart()
  }

  // ---------- media ----------
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: {
    for (var i = 0; i < players.length; i++)
      if (players[i] && players[i].isPlaying) return players[i]
    return players.length > 0 ? players[0] : null
  }
  readonly property bool hasMedia: !!(player && player.trackTitle)

  // ---------- network ----------
  property var netInfo: ({})
  readonly property string networkSubtitle: {
    if (netInfo.type === "wifi") return netInfo.ssid || "Connected"
    if (netInfo.type === "ethernet") return "Ethernet"
    return Networking.wifiEnabled ? "Not connected" : "Off"
  }
  readonly property string networkIcon: {
    if (netInfo.type === "ethernet") return "󰈀"
    return Networking.wifiEnabled ? "󰖩" : "󰖪"
  }

  // ---------- bluetooth ----------
  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property bool btOn: !!(btAdapter && btAdapter.enabled)
  readonly property string btSubtitle: {
    if (!btAdapter) return "Unavailable"
    if (!btOn) return "Off"
    var devs = Bluetooth.devices ? Bluetooth.devices.values : []
    for (var i = 0; i < devs.length; i++)
      if (devs[i] && devs[i].connected) return devs[i].name || "Connected"
    return "On"
  }

  // ---------- sound ----------
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
  PwObjectTracker { objects: root.sink ? [root.sink] : [] }

  // ---------- display ----------
  property bool brightnessAvailable: false
  property real brightness: 0
  property string focusedMonitor: ""

  // ---------- system line ----------
  property string uptimeText: ""
  property string tempText: ""
  readonly property string subtitleLine: {
    var parts = []
    if (uptimeText) parts.push("up " + uptimeText)
    if (tempText) parts.push(tempText)
    return parts.join("  ·  ")
  }

  function refresh() {
    if (!netProc.running) netProc.running = true
    if (!monitorProc.running) monitorProc.running = true
    if (!statsProc.running) statsProc.running = true
    if (!stateProc.running) stateProc.running = true
  }

  function run(cmd) { Quickshell.execDetached(cmd) }

  // Close first so screenshots and menus don't catch the card.
  function runAfterClose(script) {
    root.close()
    run(["bash", "-c", "sleep 0.25; " + script])
  }

  function openBuiltin(target) {
    root.close()
    run(["bash", "-c", "sleep 0.15; omarchy-shell " + target + " open"])
  }

  function setBrightness(v) {
    brightness = Math.max(0.01, Math.min(1, v))
    brightnessDebounce.restart()
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      openAnim.restart()
    } else {
      openAnim.stop()
      closeAnim.restart()
    }
  }

  // The card belongs to KeyboardPanel; reach it through the content holder
  // and give it a spring "drop from the avatar" on open.
  property Item card: null
  Scale {
    id: cardScale
    origin.x: root.card ? root.card.width : 0
    origin.y: 0
    xScale: 1
    yScale: 1
  }
  Translate { id: cardShift; y: 0 }

  ParallelAnimation {
    id: openAnim
    NumberAnimation { target: cardScale; properties: "xScale,yScale"; from: 0.86; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.15 }
    NumberAnimation { target: cardShift; property: "y"; from: -14; to: 0; duration: 380; easing.type: Easing.OutCubic }
    SequentialAnimation {
      PropertyAction { target: column; property: "opacity"; value: 0 }
      PauseAnimation { duration: 70 }
      ParallelAnimation {
        NumberAnimation { target: column; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation { target: column; property: "y"; from: 8; to: 0; duration: 320; easing.type: Easing.OutCubic }
      }
    }
  }

  ParallelAnimation {
    id: closeAnim
    NumberAnimation { target: cardScale; properties: "xScale,yScale"; to: 0.94; duration: 140; easing.type: Easing.InCubic }
    NumberAnimation { target: cardShift; property: "y"; to: -6; duration: 140; easing.type: Easing.InCubic }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: netProc
    command: ["omarchy-network-status", "--verbose"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var info = {}
        String(text || "").split("\n").forEach(function(line) {
          var i = line.indexOf("\t")
          if (i > 0) info[line.slice(0, i)] = line.slice(i + 1)
        })
        root.netInfo = info
      }
    }
  }

  Process {
    id: monitorProc
    command: ["omarchy-monitor-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var b = String(lines[0] || "").trim()
        root.brightnessAvailable = b !== "" && b !== "unavailable"
        if (root.brightnessAvailable) root.brightness = Math.max(0, Math.min(100, parseInt(b, 10))) / 100
        root.focusedMonitor = String(lines[5] || "").trim()
      }
    }
  }

  Process {
    id: statsProc
    command: ["bash", "-c",
      "uptime -p | sed 's/^up //; s/ hours\\?/h/; s/ minutes\\?/m/; s/ days\\?/d/; s/,//g'; " +
      "~/.config/omarchy/bar/scripts/cpu-temp 2>/dev/null | jq -r '.text // empty' | tr -d ' '"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        root.uptimeText = String(lines[0] || "").trim()
        root.tempText = String(lines[1] || "").replace(/[^0-9°C]/g, "")
      }
    }
  }

  Process { id: brightnessProc }

  Process {
    id: stateProc
    command: ["bash", "-c",
      "omarchy-shell notifications isDnd 2>/dev/null; " +
      "omarchy-toggle-nightlight --status 2>/dev/null | jq -r .enabled; " +
      "omarchy-toggle-idle status 2>/dev/null | jq -r .enabled"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var l = String(text || "").split("\n")
        root.dndOn = String(l[0] || "").trim() === "on"
        root.nightOn = String(l[1] || "").trim() === "true"
        root.awakeOn = String(l[2] || "").trim() === "true"
      }
    }
  }

  Timer {
    id: stateRefresh
    interval: 700
    onTriggered: if (!stateProc.running) stateProc.running = true
  }

  Timer {
    id: brightnessDebounce
    interval: 120
    onTriggered: {
      if (brightnessProc.running) { restart(); return }
      var args = ["omarchy-brightness-display", "--no-osd"]
      if (root.focusedMonitor) args.push("--monitor", root.focusedMonitor)
      args.push(Math.round(root.brightness * 100) + "%")
      brightnessProc.command = args
      brightnessProc.running = true
    }
  }

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  // ================= bar button: the profile picture =================
  Item {
    id: button
    anchors.fill: parent
    implicitWidth: Style.bar.iconSlot
    implicitHeight: root.bar ? root.bar.barSize : Style.bar.sizeHorizontal

    Avatar {
      // Whole-pixel position and an even size keep the small circle crisp.
      x: Math.round((parent.width - width) / 2)
      y: Math.round((parent.height - height) / 2)
      size: 2 * Math.round(Math.max(16, (root.bar ? root.bar.barSize : Style.bar.sizeHorizontal) - 6) / 2)
      ring: root.opened
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggle()
    }
  }

  // ================= the card =================
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      Component.onCompleted: {
        var holder = keyCatcher.parent
        root.card = holder ? holder.parent : null
        if (root.card) {
          root.card.transform = [cardScale, cardShift]
          // Translucent card so Hyprland's blur (omarchy-keyboard-panel layer
          // rule, ignore_alpha 0.3) frosts what's behind it, like the launcher.
          root.card.color = Qt.binding(function() {
            var bg = Color.popups.background
            return Qt.rgba(bg.r, bg.g, bg.b, 0.5)
          })
          // No accent border: the frosted edge is enough.
          root.card.borderSpec = Border.flat("transparent", 0)
        }
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: root.gap

        // ---------- header: avatar · name · lock / power ----------
        Item {
          width: parent.width
          height: Style.space(48)

          Avatar {
            id: headerAvatar
            size: Style.space(44)
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            anchors.left: headerAvatar.right
            anchors.leftMargin: Style.space(12)
            anchors.right: headerButtons.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: root.userName
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: root.subtitleLine
              visible: text !== ""
              color: root.fg
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Row {
            id: headerButtons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            RoundButton { size: Style.space(32); icon: "󰌾"; onClicked: root.runAfterClose("omarchy system lock") }
            RoundButton { size: Style.space(32); icon: "󰐥"; onClicked: root.runAfterClose("omarchy menu toggle system") }
          }
        }

        // ---------- network + bluetooth | now playing ----------
        Row {
          width: parent.width
          spacing: root.gap
          readonly property real half: (width - spacing) / 2

          Column {
            width: parent.half
            spacing: root.gap

            ToggleTile {
              width: parent.width
              icon: root.networkIcon
              title: "Wi-Fi"
              subtitle: root.networkSubtitle
              active: Networking.wifiEnabled
              onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
              onOpened: root.openBuiltin("omarchy.network")
            }

            ToggleTile {
              width: parent.width
              icon: root.btOn ? "󰂯" : "󰂲"
              title: "Bluetooth"
              subtitle: root.btSubtitle
              active: root.btOn
              onToggled: root.run(["omarchy-bluetooth-power", "toggle"])
              onOpened: root.openBuiltin("omarchy.bluetooth")
            }
          }

          NowPlaying {
            width: parent.half
            height: Style.space(56) * 2 + root.gap
          }
        }

        // ---------- focus | night light | stay awake ----------
        Row {
          width: parent.width
          spacing: root.gap
          readonly property real half: (width - spacing) / 2

          ToggleTile {
            width: parent.half
            icon: "󰽥"
            title: "Focus"
            subtitle: active ? "Do Not Disturb" : "Off"
            active: root.dndOn
            onToggled: root.toggleState("dnd", "omarchy-toggle-notification-silencing")
            onOpened: root.toggleState("dnd", "omarchy-toggle-notification-silencing")
          }

          SquareTile {
            width: (parent.half - root.gap) / 2
            icon: "󰔎"
            active: root.nightOn
            onClicked: root.toggleState("night", "omarchy-toggle-nightlight")
          }

          SquareTile {
            width: (parent.half - root.gap) / 2
            icon: "󰅶"
            active: root.awakeOn
            onClicked: root.toggleState("awake", "omarchy-toggle-idle toggle")
          }
        }

        // ---------- display ----------
        SliderCard {
          visible: root.brightnessAvailable
          width: parent.width
          label: "Display"
          icon: "󰃠"
          value: root.brightness
          onMoved: function(v) { root.setBrightness(v) }
          onOpened: root.openBuiltin("omarchy.monitor")
        }

        // ---------- sound ----------
        SliderCard {
          width: parent.width
          label: "Sound"
          icon: root.muted || root.volume <= 0.001 ? "󰝟" : (root.volume < 0.5 ? "󰖀" : "󰕾")
          value: root.muted ? 0 : Math.min(1, root.volume)
          onMoved: function(v) {
            if (!root.sink || !root.sink.audio) return
            root.sink.audio.muted = false
            root.sink.audio.volume = v
          }
          onIconClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
          onOpened: root.openBuiltin("omarchy.audio")
        }

        // ---------- quick actions ----------
        Row {
          width: parent.width
          readonly property int count: 5
          readonly property real size: Style.space(44)
          spacing: (width - size * count) / (count - 1)

          RoundButton { size: parent.size; icon: "󰹑"; onClicked: root.runAfterClose("omarchy capture screenshot") }
          RoundButton { size: parent.size; icon: "󰻃"; onClicked: root.runAfterClose("omarchy capture screenrecording") }
          RoundButton { size: parent.size; icon: "󰅌"; onClicked: root.runAfterClose("omarchy menu clipboard") }
          RoundButton { size: parent.size; icon: "󰏘"; onClicked: root.runAfterClose("omarchy menu summon style.theme") }
          RoundButton { size: parent.size; icon: "󰀻"; onClicked: root.runAfterClose("omarchy menu") }
        }
      }
    }
  }

  // ================= components =================

  component Avatar: Item {
    id: av
    property real size: 18
    property bool ring: false
    width: size
    height: size

    // Photo, clipped to a circle (only when ~/.face exists).
    ClippingRectangle {
      anchors.fill: parent
      radius: width / 2
      color: "transparent"
      visible: avatarImage.status === Image.Ready

      Image {
        id: avatarImage
        anchors.fill: parent
        source: root.avatarPath !== "" ? "file://" + root.avatarPath : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        sourceSize.width: av.size * 2
        sourceSize.height: av.size * 2
      }
    }

    // Fallback: drawn directly (not through the clip texture) so the circle
    // edge and the initial render crisp at bar size.
    Rectangle {
      anchors.fill: parent
      visible: avatarImage.status !== Image.Ready
      radius: width / 2
      antialiasing: true
      color: root.accent
    }

    Text {
      visible: avatarImage.status !== Image.Ready
      x: Math.round((av.width - implicitWidth) / 2)
      y: Math.round((av.height - implicitHeight) / 2)
      text: root.userName.charAt(0).toUpperCase()
      color: root.contrast
      font.family: "Noto Sans"
      font.pixelSize: Math.round(av.size * 0.55)
      font.weight: Font.DemiBold
      font.hintingPreference: Font.PreferFullHinting
      renderType: Text.NativeRendering
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: -2
      radius: width / 2
      color: "transparent"
      border.width: 1.5
      border.color: root.accent
      opacity: av.ring ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
  }

  // Shared press/hover feel: subtle brighten on hover, spring on press.
  component Pressable: Rectangle {
    id: pr
    property bool hovered: hover.hovered
    property bool pressed: false
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, hovered ? 0.11 : 0.07)
    scale: pressed ? 0.96 : 1
    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on scale { SpringAnimation { spring: 5; damping: 0.32; epsilon: 0.002 } }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
  }

  component IconCircle: Rectangle {
    property string icon: ""
    property bool active: false
    radius: width / 2
    color: active ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

    Text {
      anchors.centerIn: parent
      text: parent.icon
      color: parent.active ? root.contrast : root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
      Behavior on color { ColorAnimation { duration: 180 } }
    }
  }

  component ToggleTile: Pressable {
    id: tile
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool active: false
    signal toggled()
    signal opened()

    height: Style.space(56)
    radius: height / 2

    MouseArea {
      anchors.fill: parent
      onPressed: tile.pressed = true
      onReleased: tile.pressed = false
      onCanceled: tile.pressed = false
      onClicked: tile.opened()
    }

    IconCircle {
      id: circle
      width: Style.space(38)
      height: width
      anchors.left: parent.left
      anchors.leftMargin: Style.space(9)
      anchors.verticalCenter: parent.verticalCenter
      icon: tile.icon
      active: tile.active
      scale: circleArea.pressed ? 0.9 : 1
      Behavior on scale { SpringAnimation { spring: 5; damping: 0.32; epsilon: 0.002 } }

      MouseArea {
        id: circleArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.toggled()
      }
    }

    Column {
      anchors.left: circle.right
      anchors.leftMargin: Style.space(9)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        width: parent.width
        text: tile.title
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: tile.subtitle
        color: root.fg
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }

  component SquareTile: Pressable {
    id: sq
    property string icon: ""
    property bool active: false
    signal clicked()

    height: Style.space(56)
    radius: Style.space(18)

    IconCircle {
      anchors.centerIn: parent
      width: Style.space(34)
      height: width
      icon: sq.icon
      active: sq.active
    }

    MouseArea {
      anchors.fill: parent
      onPressed: sq.pressed = true
      onReleased: sq.pressed = false
      onCanceled: sq.pressed = false
      onClicked: sq.clicked()
    }
  }

  component RoundButton: Pressable {
    id: rb
    property real size: Style.space(44)
    property string icon: ""
    signal clicked()

    width: size
    height: size
    radius: size / 2

    Text {
      anchors.centerIn: parent
      text: rb.icon
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Math.round(rb.size * 0.4)
    }

    MouseArea {
      anchors.fill: parent
      onPressed: rb.pressed = true
      onReleased: rb.pressed = false
      onCanceled: rb.pressed = false
      onClicked: rb.clicked()
    }
  }

  component NowPlaying: Rectangle {
    id: np
    readonly property bool hasMedia: root.hasMedia
    radius: Style.space(18)
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.07)
    clip: true

    // Album art as a soft wash behind the text.
    Image {
      anchors.fill: parent
      source: np.hasMedia && root.player.trackArtUrl ? root.player.trackArtUrl : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      opacity: status === Image.Ready ? 0.22 : 0
      Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(12)
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: np.hasMedia ? root.player.trackTitle : "Not Playing"
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: np.hasMedia ? (root.player.trackArtist || "") : ""
        visible: text !== ""
        color: root.fg
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(12)
      spacing: Style.space(14)
      opacity: np.hasMedia ? 1 : 0.35

      MediaButton { icon: "󰒮"; onClicked: if (root.player) root.player.previous() }
      MediaButton {
        icon: root.player && root.player.isPlaying ? "󰏤" : "󰐊"
        big: true
        onClicked: if (root.player) root.player.togglePlaying()
      }
      MediaButton { icon: "󰒭"; onClicked: if (root.player) root.player.next() }
    }
  }

  component MediaButton: Text {
    id: mb
    property string icon: ""
    property bool big: false
    signal clicked()
    text: icon
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: big ? Style.font.display : Style.font.heading
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    scale: mbArea.pressed ? 0.85 : 1
    Behavior on scale { SpringAnimation { spring: 5; damping: 0.32; epsilon: 0.002 } }

    MouseArea {
      id: mbArea
      anchors.fill: parent
      anchors.margins: -6
      cursorShape: Qt.PointingHandCursor
      onClicked: mb.clicked()
    }
  }

  component SliderCard: Rectangle {
    id: sc
    property string label: ""
    property string icon: ""
    property real value: 0
    signal moved(real v)
    signal iconClicked()
    signal opened()

    radius: Style.space(18)
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.07)
    implicitHeight: cardColumn.implicitHeight + Style.space(24)
    height: implicitHeight

    Column {
      id: cardColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(8)

      Text {
        text: sc.label
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: sc.opened()
        }
      }

      Item {
        id: track
        width: parent.width
        height: Style.space(26)
        readonly property real shown: dragArea.pressed ? dragArea.live : sc.value

        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
        }

        Rectangle {
          height: parent.height
          radius: height / 2
          width: Math.max(height, parent.width * Math.max(0, Math.min(1, track.shown)))
          color: root.fg
          opacity: 0.92
          Behavior on width {
            enabled: !dragArea.pressed
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
          }
        }

        MouseArea {
          id: dragArea
          property real live: 0
          anchors.fill: parent
          anchors.leftMargin: track.height
          cursorShape: Qt.PointingHandCursor
          function update(x) {
            live = Math.max(0, Math.min(1, (x + track.height) / track.width))
            sc.moved(live)
          }
          onPressed: function(mouse) { update(mouse.x) }
          onPositionChanged: function(mouse) { if (pressed) update(mouse.x) }
          onWheel: function(wheel) {
            sc.moved(Math.max(0, Math.min(1, sc.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
          }
        }

        // Icon sits on the fill's rounded start, like macOS.
        Text {
          width: track.height
          height: track.height
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: sc.icon
          color: root.contrast
          font.family: root.fontFamily
          font.pixelSize: Style.font.body

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sc.iconClicked()
          }
        }
      }
    }
  }
}
