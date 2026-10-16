import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// macOS menu-bar style: the focused app's name in bold ("Files", not the
// window title). Click focuses it, middle-click closes it.
BarWidget {
  id: root
  moduleName: "mehexi.app-name"

  readonly property var toplevel: ToplevelManager.activeToplevel
  readonly property string appId: toplevel ? String(toplevel.appId || "") : ""
  readonly property string appName: {
    if (!appId) return "Desktop"
    var entry = DesktopEntries.heuristicLookup(appId)
    if (entry && entry.name) return entry.name
    // org.gnome.Nautilus -> Nautilus, foot -> Foot
    var last = appId.split(".").pop()
    return last.charAt(0).toUpperCase() + last.slice(1)
  }

  visible: !vertical
  implicitWidth: visible ? Math.min(Style.space(200), label.implicitWidth) : 0
  implicitHeight: barSize

  Behavior on implicitWidth {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  Text {
    id: label
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    textFormat: Text.PlainText
    text: root.appName
    elide: Text.ElideRight
    color: root.bar ? root.bar.barForeground : Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    font.bold: true
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (!root.toplevel) return
      if (mouse.button === Qt.MiddleButton) root.toplevel.close()
      else root.toplevel.activate()
    }
  }
}
