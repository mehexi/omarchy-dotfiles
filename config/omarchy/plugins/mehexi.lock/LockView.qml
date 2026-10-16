import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Ui

// macOS Tahoe-style lock screen, in two states:
//   idle     - sharp wallpaper, date + big clock at the top, small avatar,
//              name and hint at the bottom.
//   password - any key or click blurs and dims the wallpaper, the clock fades
//              away, and a larger avatar, name and frosted password field
//              move to the centre. Drops back to idle after a quiet spell.
//
// The properties and signals below are the contract with Service.qml (PAM,
// fingerprint, failure handling) and are kept identical to Omarchy's view.
Item {
  id: root

  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  // ---------- look ----------
  readonly property string home: Quickshell.env("HOME")
  readonly property string avatarPath: home + "/.face"
  readonly property string userName: {
    var u = Quickshell.env("USER") || "user"
    return u.charAt(0).toUpperCase() + u.slice(1)
  }
  readonly property string sans: "Noto Sans"
  readonly property color ink: "#ffffff"
  readonly property bool errorState: failureMessage.length > 0
  readonly property string hintText: fingerprintConfigured ? "Touch the fingerprint reader or enter password" : "Enter Password"

  // 0 = idle (clock), 1 = password entry.
  property real mode: 0
  property bool passwordMode: false
  property bool revealPassword: false
  property date now: new Date()

  Behavior on mode { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
  onPasswordModeChanged: mode = passwordMode ? 1 : 0

  function enterPasswordMode() {
    passwordMode = true
    idleTimer.restart()
    forcePasswordFocus()
  }

  // Cache-busts the lock background by appending `?v=` so a background
  // changed mid-session reloads.
  function fileUrl(path) {
    if (!path) return ""
    var encoded = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded + "?v=" + backgroundVersion
  }

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  onFailedAttemptsChanged: {
    if (failedAttempts > 0) {
      enterPasswordMode()
      shake.restart()
    }
  }
  onFailureMessageChanged: if (errorState) enterPasswordMode()
  onAuthenticatingPasswordChanged: if (authenticatingPassword) enterPasswordMode()

  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
    intro.start()
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.now = new Date()
  }

  // Back to the clock after a quiet spell with nothing typed.
  Timer {
    id: idleTimer
    interval: 12000
    onTriggered: {
      if (passwordInput.text.length === 0 && !root.authenticatingPassword) {
        root.passwordMode = false
        root.revealPassword = false
      }
    }
  }

  // ---------- background ----------
  Rectangle {
    anchors.fill: parent
    color: Color.background

    Image {
      id: wallpaper
      anchors.fill: parent
      source: root.loadBackground ? root.fileUrl(root.backgroundPath) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize.width: width
      sourceSize.height: height
    }

    // Blurred copy that fades in for password entry.
    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper
      autoPaddingEnabled: false
      blurEnabled: root.loadBackground && wallpaper.status === Image.Ready
      blur: 1.0
      blurMax: 96
      blurMultiplier: 1.1
      saturation: 0.1
      opacity: root.mode
    }

    // Light top/bottom shading keeps white text readable on bright walls.
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.22) }
        GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0.0) }
        GradientStop { position: 0.75; color: Qt.rgba(0, 0, 0, 0.0) }
        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.25) }
      }
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.18 * root.mode)
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.enterPasswordMode() }
      onPositionChanged: root.wakeRequested()
    }
  }

  // ---------- idle: date + big clock ----------
  Column {
    id: clock
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.height * 0.07 - root.mode * Style.space(30) + (1 - introProgress) * -Style.space(20)
    opacity: (1 - root.mode) * introProgress
    visible: opacity > 0.01
    spacing: -Math.round(root.height * 0.012)

    property real introProgress: 0

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatDate(root.now, "dddd, MMMM d")
      color: root.ink
      opacity: 0.9
      font.family: root.sans
      font.pixelSize: Math.round(root.height * 0.03)
      font.weight: Font.DemiBold
    }

    Text {
      id: timeText
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatTime(root.now, "HH:mm")
      color: root.ink
      opacity: 0.88
      font.family: root.sans
      font.pixelSize: Math.round(root.height * 0.19)
      font.weight: Font.Bold
      font.letterSpacing: -Math.round(root.height * 0.004)

      layer.enabled: true
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.35)
        shadowBlur: 0.6
        shadowVerticalOffset: 2
      }
    }
  }

  // ---------- user block: small at the bottom, large in the centre ----------
  Item {
    id: userBlock
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.max(field.width, Style.space(260))
    height: column.implicitHeight

    readonly property real idleY: root.height - height - root.height * 0.07
    readonly property real activeY: root.height * 0.5 - avatar.height * 0.9
    y: idleY + (activeY - idleY) * root.mode
    opacity: clock.introProgress

    Column {
      id: column
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(8) + root.mode * Style.space(4)

      // Avatar grows from 40 to 88 px between the two states.
      Item {
        id: avatar
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.round(Style.space(40) + root.mode * Style.space(48))
        height: width

        ClippingRectangle {
          anchors.fill: parent
          radius: width / 2
          color: Qt.rgba(1, 1, 1, 0.25)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.35)

          Image {
            id: avatarImage
            anchors.fill: parent
            source: "file://" + root.avatarPath
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            smooth: true
            mipmap: true
            sourceSize.width: 192
            sourceSize.height: 192
            visible: status === Image.Ready
          }

          Text {
            anchors.centerIn: parent
            visible: avatarImage.status !== Image.Ready
            text: root.userName.charAt(0)
            color: root.ink
            font.family: root.sans
            font.pixelSize: Math.round(avatar.width * 0.45)
            font.weight: Font.DemiBold
          }
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.userName
        color: root.ink
        font.family: root.sans
        font.pixelSize: Math.round(Style.font.body + root.mode * Style.space(5))
        font.weight: Font.DemiBold
      }

      // Password field: collapsed to nothing while idle.
      Item {
        id: fieldSlot
        anchors.horizontalCenter: parent.horizontalCenter
        width: field.width
        height: field.height * root.mode
        opacity: root.mode

        Rectangle {
          id: field
          width: Style.space(230)
          height: Style.space(34)
          radius: height / 2
          color: Qt.rgba(1, 1, 1, root.errorState ? 0.16 : 0.2)
          border.width: 1
          border.color: root.errorState ? Qt.rgba(1, 0.45, 0.45, 0.7) : Qt.rgba(1, 1, 1, 0.3)
          Behavior on border.color { ColorAnimation { duration: 180 } }
          transform: Translate { id: shakeShift; x: 0 }

          TextInput {
            id: passwordInput
            anchors.left: parent.left
            anchors.right: eye.left
            anchors.leftMargin: Style.space(14)
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            verticalAlignment: TextInput.AlignVCenter
            activeFocusOnPress: true
            clip: true
            enabled: root.inputEnabled && !root.authenticatingPassword
            readOnly: root.authenticatingPassword
            echoMode: root.revealPassword ? TextInput.Normal : TextInput.Password
            passwordCharacter: "●"
            passwordMaskDelay: 0
            color: root.ink
            selectionColor: Qt.rgba(1, 1, 1, 0.35)
            selectedTextColor: root.ink
            font.family: root.sans
            font.pixelSize: Style.font.body
            font.letterSpacing: root.revealPassword ? 0 : 2
            cursorVisible: activeFocus && root.passwordMode && !root.authenticatingPassword
            cursorDelegate: Rectangle {
              width: 2
              color: root.ink
              visible: passwordInput.cursorVisible
            }

            onTextChanged: {
              if (!root.syncingPasswordText) root.passwordTextEdited(text)
              if (text.length > 0) {
                root.wakeRequested()
                root.enterPasswordMode()
              }
              if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
            }

            onAccepted: {
              var submitted = root.passwordText
              root.passwordTextEdited("")
              if (submitted.length > 0) root.submitPassword(submitted)
            }

            Keys.onPressed: function(event) {
              root.wakeRequested()
              if (event.key === Qt.Key_Escape) {
                if (passwordInput.text.length > 0) root.passwordTextEdited("")
                else root.passwordMode = false
                event.accepted = true
                return
              }
              if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U) {
                root.passwordTextEdited("")
                event.accepted = true
                return
              }
              root.enterPasswordMode()
            }

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: passwordInput.text.length === 0
              text: root.authenticatingPassword ? "Checking…" : "Enter Password"
              color: root.ink
              opacity: 0.55
              font.family: root.sans
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }

          // Show / hide password, like the macOS eye.
          Text {
            id: eye
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: root.revealPassword ? "󰈈" : "󰈉"
            color: root.ink
            opacity: eyeArea.containsMouse ? 0.95 : 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.title

            MouseArea {
              id: eyeArea
              anchors.fill: parent
              anchors.margins: -6
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.revealPassword = !root.revealPassword
                root.forcePasswordFocus()
              }
            }
          }
        }
      }

      // Hint under the field (or under the name while idle); errors replace it.
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        // In password mode the field's placeholder already says it; keep the
        // line for errors and the fingerprint hint only.
        text: root.errorState ? root.failureMessage
          : (root.passwordMode && !root.fingerprintConfigured ? " " : root.hintText)
        color: root.errorState ? "#ffb4b4" : root.ink
        opacity: root.errorState ? 0.95 : 0.7
        font.family: root.sans
        font.pixelSize: Style.font.caption + 1
      }
    }
  }

  // Head-shake on a wrong password.
  SequentialAnimation {
    id: shake
    NumberAnimation { target: shakeShift; property: "x"; to: -14; duration: 50; easing.type: Easing.OutQuad }
    NumberAnimation { target: shakeShift; property: "x"; to: 12; duration: 70; easing.type: Easing.InOutQuad }
    NumberAnimation { target: shakeShift; property: "x"; to: -8; duration: 60; easing.type: Easing.InOutQuad }
    NumberAnimation { target: shakeShift; property: "x"; to: 5; duration: 50; easing.type: Easing.InOutQuad }
    NumberAnimation { target: shakeShift; property: "x"; to: 0; duration: 50; easing.type: Easing.OutQuad }
  }

  // Lock-in: clock drops into place and everything fades up.
  NumberAnimation {
    id: intro
    target: clock
    property: "introProgress"
    from: 0
    to: 1
    duration: 650
    easing.type: Easing.OutCubic
  }
}
