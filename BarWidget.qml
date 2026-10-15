import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TranslatorModel.js" as Model

// BarWidget for Translator plugin
BarWidget {
  id: root
  moduleName: "cjoy720.translator"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string homeDir: Quickshell.env("HOME") || ""
  readonly property string settingsPath: (Quickshell.env("XDG_STATE_HOME") || (homeDir + "/.local/state")) + "/cjoy720.translator/settings.json"

  property string targetLang: "EN"
  property string currentEngine: "google"

  Process {
    id: settingsReader
    command: ["cat", root.settingsPath]
    stdout: StdioCollector {
      id: settingsOut
      waitForEnd: true
    }
    stderr: StdioCollector {}
    onExited: function(exitCode) {
      if (exitCode === 0 && settingsOut.text) {
        var s = Model.safeParse(settingsOut.text)
        if (s) {
          root.targetLang = (s.targetLanguage || "en").toUpperCase()
          root.currentEngine = s.defaultEngine || "google"
        }
      }
    }
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: settingsReader.running = true
  }

  readonly property string barTooltip: "Translator (" + root.currentEngine.toUpperCase() + " ➜ " + root.targetLang + ")\nLeft click: Open / Toggle\nRight click: Translate Selection"

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰗊"
    labelVisible: true
    hasVisualContent: true
    tooltipText: root.barTooltip

    onPressed: function(b) {
      if (!root.bar || typeof root.bar.run !== "function") return
      if (b === Qt.RightButton) {
        root.bar.run("omarchy-shell translator translate")
      } else {
        root.bar.run("omarchy-shell translator toggle")
      }
    }
  }

  // Language badge overlay
  Rectangle {
    visible: !root.vertical && root.targetLang !== ""
    anchors.top: parent.top
    anchors.topMargin: -Style.space(2)
    anchors.right: parent.right
    anchors.rightMargin: -Style.space(2)
    width: Math.max(Style.space(16), badgeLabel.implicitWidth + Style.space(6))
    height: Style.space(14)
    radius: height / 2
    color: Color.accent
    border.width: 1
    border.color: Color.bar.background

    Text {
      id: badgeLabel
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: root.targetLang
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Style.space(8)
      font.bold: true
    }
  }
}
