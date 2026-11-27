import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui

// Battery of the connected Bluetooth devices. The bar shows one icon + percent
// per device that reports a level; clicking opens a list with a gauge each.
// The widget takes no space on the bar when nothing reports a battery.
Panel {
  id: root
  moduleName: "mehexi.bt-battery"
  ipcTarget: "mehexi.bt-battery"

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool showName: setting("showName", false)
  readonly property int warnAt: setting("warnAt", 30)
  readonly property int criticalAt: setting("criticalAt", 15)
  readonly property int maxInBar: setting("maxInBar", 2)

  // Quickshell singletons are lazy: bind it at load, never first-touch it
  // inside a timer callback (that returns an empty adapter list for the tick).
  property var bt: Bluetooth
  readonly property var adapter: bt ? bt.defaultAdapter : null
  readonly property var btDevices: bt && bt.devices ? bt.devices.values : []

  // ---------- live entries, straight from BlueZ via Quickshell ----------
  readonly property var liveEntries: {
    var out = []
    for (var i = 0; i < btDevices.length; i++) {
      var d = btDevices[i]
      if (!d || !d.connected || !d.batteryAvailable) continue
      out.push({
        addr: d.address || "",
        name: d.name || d.deviceName || d.address || "Device",
        icon: d.icon || "",
        pct: Math.round((d.battery || 0) * 100)
      })
    }
    return out
  }

  // ---------- fallback ----------
  // This machine's Bluetooth is a USB dongle: when org.bluez registers after
  // the shell started, `Bluetooth.defaultAdapter` stays null for the life of
  // the process. Poll bluetoothctl only in that case, so the widget still
  // works until the next `omarchy restart shell`.
  readonly property bool needsFallback: !adapter
  property var fallbackEntries: []

  readonly property var entries: liveEntries.length > 0 ? liveEntries : fallbackEntries
  readonly property var barEntries: entries.slice(0, Math.max(1, maxInBar))
  readonly property int worst: {
    var w = -1
    for (var i = 0; i < entries.length; i++)
      if (w < 0 || entries[i].pct < w) w = entries[i].pct
    return w
  }

  readonly property bool hasBattery: entries.length > 0
  onHasBatteryChanged: if (!hasBattery) close()

  // Nothing to report -> the bar slot collapses to zero width (no empty pill).
  visible: hasBattery
  implicitWidth: hasBattery ? button.implicitWidth : 0
  implicitHeight: hasBattery ? button.implicitHeight : 0

  Process {
    id: probe
    command: ["bash", "-lc",
      "for m in $(bluetoothctl devices Connected 2>/dev/null | awk '{print $2}'); do " +
      "bluetoothctl info \"$m\" 2>/dev/null | awk -v m=\"$m\" '" +
      "/^\\tName:/{n=substr($0, index($0,$2))} " +
      "/^\\tIcon:/{i=$2} " +
      "/^\\tBattery Percentage:/{gsub(/[()]/,\"\",$NF); b=$NF} " +
      "END{if (b != \"\") printf \"%s\\t%s\\t%s\\t%s\\n\", m, n, i, b}'; done"]
    stdout: StdioCollector {
      onStreamFinished: {
        var out = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i]) continue
          var f = lines[i].split("\t")
          if (f.length < 4) continue
          out.push({ addr: f[0], name: f[1] || f[0], icon: f[2] || "", pct: parseInt(f[3], 10) })
        }
        root.fallbackEntries = out
      }
    }
  }

  Timer {
    interval: root.opened ? 10000 : 60000
    running: root.needsFallback
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!probe.running) probe.running = true
  }

  // ---------- presentation ----------
  function deviceGlyph(icon) {
    var i = (icon || "").toLowerCase()
    if (i.indexOf("headphone") >= 0) return "󰋋"
    if (i.indexOf("headset") >= 0) return "󰋎"
    if (i.indexOf("mouse") >= 0) return "󰍽"
    if (i.indexOf("keyboard") >= 0) return "󰌌"
    if (i.indexOf("phone") >= 0) return "󰄜"
    if (i.indexOf("speaker") >= 0 || i.indexOf("audio-card") >= 0) return "󰓃"
    if (i.indexOf("gaming") >= 0 || i.indexOf("gamepad") >= 0) return "󰊴"
    if (i.indexOf("watch") >= 0) return "󰖉"
    if (i.indexOf("computer") >= 0 || i.indexOf("laptop") >= 0) return "󰌢"
    if (i.indexOf("printer") >= 0) return "󰐪"
    if (i.indexOf("camera") >= 0) return "󰄀"
    if (i.indexOf("display") >= 0 || i.indexOf("video") >= 0) return "󰍹"
    return "󰂯"
  }

  function levelColor(pct) {
    if (pct < 0) return root.fg
    if (pct <= root.criticalAt) return "#ff6b6b"
    if (pct <= root.warnAt) return "#ffb454"
    return root.fg
  }

  // ================= bar button =================
  Item {
    id: button
    anchors.fill: parent
    implicitWidth: barRow.implicitWidth + Style.space(12)
    implicitHeight: root.bar ? root.bar.barSize : Style.bar.sizeHorizontal

    Row {
      id: barRow
      anchors.centerIn: parent
      spacing: Style.space(8)

      Repeater {
        model: root.barEntries

        Row {
          spacing: Style.space(4)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.deviceGlyph(modelData.icon)
            color: root.levelColor(modelData.pct)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showName
            text: modelData.name
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.pct + "%"
            color: root.levelColor(modelData.pct)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      // "+2" when more devices are connected than the bar shows.
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.entries.length > root.barEntries.length
        text: "+" + (root.entries.length - root.barEntries.length)
        color: root.fg
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggle()
    }
  }

  // ================= popup list =================
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(280))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        PanelSectionHeader { width: parent.width; text: "Bluetooth battery" }

        Repeater {
          model: root.entries

          Column {
            width: column.width
            spacing: Style.space(4)

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.deviceGlyph(modelData.icon)
                color: root.levelColor(modelData.pct)
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Style.space(8) * 2 - Style.space(26) - pctLabel.width
                elide: Text.ElideRight
                text: modelData.name
                color: Color.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                id: pctLabel
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.pct + "%"
                color: root.levelColor(modelData.pct)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }

            // Gauge
            Rectangle {
              width: parent.width
              height: Style.space(6)
              radius: height / 2
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)

              Rectangle {
                width: Math.max(parent.height, parent.width * Math.max(0, Math.min(100, modelData.pct)) / 100)
                height: parent.height
                radius: height / 2
                color: root.levelColor(modelData.pct)
                Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: root.needsFallback
          wrapMode: Text.WordWrap
          text: "No adapter in the shell — polling bluetoothctl. Run `omarchy restart shell` after plugging the dongle in."
          color: Color.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
