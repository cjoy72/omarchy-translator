import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "TranslatorModel.js" as Model

// Floating Translator Window: Layer-shell popup anchored at cursor location
Item {
  id: panelRoot

  property var controller: null
  property bool opened: false
  property int anchorX: 24
  property int anchorY: 24

  readonly property int cardWidth: Style.space(450)
  readonly property int edgeMargin: Style.space(10)
  readonly property int cardHeightPx: card.height
  readonly property int cardEstimatedHeight: Style.space(220)

  // Derived from the controller's probed monitor (same as OmaDrop)
  readonly property int monitorWidth: controller && controller.pendingMonitor ? controller.pendingMonitor.width : 1280
  readonly property int monitorHeight: controller && controller.pendingMonitor ? controller.pendingMonitor.height : 800
  property string screenName: ""

  function useScreen(name) {
    panelRoot.screenName = String(name || "")
    var screens = Quickshell.screens || []
    var names = []
    for (var i = 0; i < screens.length; i++) {
      names.push(screens[i].name)
      if (screens[i].name === panelRoot.screenName) {
        panel.screen = screens[i]
        return
      }
    }
    console.warn("translator: screen '" + panelRoot.screenName + "' not found; have: " + names.join(", "))
  }

  function requestClose() {
    showLanguagePicker = false
    showEnginePicker = false
    showSettings = false
    if (controller) controller.dismiss()
  }

  Shortcut {
    sequence: "Escape"
    enabled: panelRoot.opened
    onActivated: panelRoot.requestClose()
  }

  Timer {
    id: copyFeedbackTimer
    interval: 1600
    repeat: false
    onTriggered: panelRoot.copiedFeedback = false
  }

  // Sub-drawer states
  property bool showLanguagePicker: false
  property bool showEnginePicker: false
  property bool showSettings: false
  property bool copiedFeedback: false

  // ---- Zone Dragging (Identical to OmaDrop) --------------------------------
  property bool draggingZone: false
  property point zonePressAnchor: Qt.point(0, 0)
  property point zonePressCursor: Qt.point(-1, -1)

  function startDrag() {
    panelRoot.zonePressAnchor = Qt.point(panelRoot.anchorX, panelRoot.anchorY)
    panelRoot.zonePressCursor = Qt.point(-1, -1)
    panelRoot.draggingZone = true
    if (panelRoot.controller) {
      cursorStream.command = ["python3", "-u", panelRoot.controller.scriptPath("cursor-stream")]
      cursorStream.running = true
    }
  }

  function stopDrag() {
    panelRoot.draggingZone = false
    cursorStream.running = false
  }

  Process {
    id: cursorStream
    stdout: SplitParser {
      onRead: function(data) {
        var parts = String(data).trim().split(",")
        if (parts.length !== 2) return
        var cx = parseFloat(parts[0])
        var cy = parseFloat(parts[1])
        if (!isFinite(cx) || !isFinite(cy) || !panelRoot.draggingZone) return
        if (panelRoot.zonePressCursor.x < 0) { panelRoot.zonePressCursor = Qt.point(cx, cy); return }
        var nx = panelRoot.zonePressAnchor.x + Math.round(cx - panelRoot.zonePressCursor.x)
        var ny = panelRoot.zonePressAnchor.y + Math.round(cy - panelRoot.zonePressCursor.y)
        var pw = panel.width > 0 ? panel.width : panelRoot.cardWidth
        var ph = panel.height > 0 ? panel.height : card.height
        panelRoot.anchorX = Math.min(Math.max(panelRoot.edgeMargin, nx),
                                     Math.max(panelRoot.edgeMargin, panelRoot.monitorWidth - pw - panelRoot.edgeMargin))
        panelRoot.anchorY = Math.min(Math.max(panelRoot.edgeMargin, ny),
                                     Math.max(panelRoot.edgeMargin, panelRoot.monitorHeight - ph - panelRoot.edgeMargin))
      }
    }
    stderr: StdioCollector {}
  }

  // ---- The Layer Window (Identical to OmaDrop) -----------------------------
  PanelWindow {
    id: panel
    visible: panelRoot.opened
    color: "transparent"

    anchors { left: true; top: true }
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "translator"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    implicitWidth: panelRoot.cardWidth
    implicitHeight: card.height

    readonly property int clampedX: Math.round(
      Math.min(Math.max(panelRoot.edgeMargin, panelRoot.anchorX),
               Math.max(panelRoot.edgeMargin, panelRoot.monitorWidth - width - panelRoot.edgeMargin)))
    readonly property int clampedY: Math.round(
      Math.min(Math.max(panelRoot.edgeMargin, panelRoot.anchorY),
               Math.max(panelRoot.edgeMargin, panelRoot.monitorHeight - height - panelRoot.edgeMargin)))

    margins.left: clampedX
    margins.top: clampedY

    // Card Surface
    Rectangle {
      id: card
      width: panelRoot.cardWidth
      height: contentCol.implicitHeight + Style.space(24)

      radius: Style.cornerRadius > 0 ? Style.cornerRadius : 12
      color: Color.popups.background
      border.width: 1
      border.color: Color.popups.border

      Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

      // Key catcher for escape
      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            panelRoot.requestClose()
            event.accepted = true
          }
        }
      }

      // Whole-card background drag: dragging any empty background, padding, or non-interactive region moves the window
      MouseArea {
        anchors.fill: parent
        hoverEnabled: false
        cursorShape: panelRoot.draggingZone ? Qt.ClosedHandCursor : Qt.ArrowCursor
        onPressed: function(mouse) { panelRoot.startDrag() }
        onReleased: function(mouse) { panelRoot.stopDrag() }
        onCanceled: function() { panelRoot.stopDrag() }
      }

      Column {
        id: contentCol
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Style.space(12)
        anchors.leftMargin: Style.space(14)
        anchors.rightMargin: Style.space(14)
        spacing: Style.space(10)

        // ---- HEADER / DRAG HANDLE -----------------------------------------
        Item {
          width: parent.width
          height: Style.space(30)

          // Draggable header area (covers header bar; badge clicks on right win over drag)
          MouseArea {
            id: headerDragMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: panelRoot.draggingZone ? Qt.ClosedHandCursor : Qt.SizeAllCursor
            onPressed: function(mouse) { panelRoot.startDrag() }
            onReleased: function(mouse) { panelRoot.stopDrag() }
            onCanceled: function() { panelRoot.stopDrag() }
          }

          // App Icon, Title & Drag Handle Grip
          Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            spacing: Style.space(6)

            Text {
              text: "󰗊"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.iconSmall || 16
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: "Translator"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: "󰇘"
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              opacity: 0.6
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // Header Badges & Actions
          Row {
            id: headerControls
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            spacing: Style.space(6)

            // Engine Selector Badge
            Rectangle {
              height: Style.space(24)
              width: engineBadgeText.implicitWidth + Style.space(14)
              radius: 6
              color: panelRoot.showEnginePicker ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25)
                                                : (engineMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
                                                                             : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.07))
              border.width: 1
              border.color: panelRoot.showEnginePicker ? Color.accent : "transparent"

              Row {
                id: engineBadgeText
                anchors.centerIn: parent
                spacing: Style.space(4)

                Text {
                  text: (controller && controller.currentEngine ? controller.currentEngine.toUpperCase() : "GOOGLE")
                  color: panelRoot.showEnginePicker ? Color.accent : Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                Text {
                  text: "▾"
                  color: Color.muted
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                id: engineMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  panelRoot.showEnginePicker = !panelRoot.showEnginePicker
                  panelRoot.showLanguagePicker = false
                  panelRoot.showSettings = false
                }
              }
            }

            // Target Language Badge
            Rectangle {
              height: Style.space(24)
              width: langBadgeText.implicitWidth + Style.space(14)
              radius: 6
              color: panelRoot.showLanguagePicker ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25)
                                                  : (langMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
                                                                             : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.07))
              border.width: 1
              border.color: panelRoot.showLanguagePicker ? Color.accent : "transparent"

              Row {
                id: langBadgeText
                anchors.centerIn: parent
                spacing: Style.space(4)

                Text {
                  text: Model.langByCode(controller ? controller.targetLanguage : "en").flag + " " +
                        Model.langByCode(controller ? controller.targetLanguage : "en").name
                  color: panelRoot.showLanguagePicker ? Color.accent : Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                Text {
                  text: "▾"
                  color: Color.muted
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                id: langMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  panelRoot.showLanguagePicker = !panelRoot.showLanguagePicker
                  panelRoot.showEnginePicker = false
                  panelRoot.showSettings = false
                }
              }
            }

            // Swap Languages Button
            Rectangle {
              height: Style.space(24)
              width: Style.space(24)
              radius: 6
              color: swapMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
                                             : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)

              Text {
                anchors.centerIn: parent
                text: "󰁯"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: swapMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (controller) controller.swapLanguages()
              }
            }

            // Close Button
            Rectangle {
              height: Style.space(24)
              width: Style.space(24)
              radius: 6
              color: closeMouse.containsMouse ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.25)
                                              : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)

              Text {
                anchors.centerIn: parent
                text: "󰅖"
                color: closeMouse.containsMouse ? Color.urgent : Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: closeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panelRoot.requestClose()
              }
            }
          }
        }

        // ---- DRAWER: ENGINE PICKER -----------------------------------------
        Rectangle {
          visible: panelRoot.showEnginePicker
          width: parent.width
          height: panelRoot.showEnginePicker ? engineFlow.implicitHeight + Style.space(16) : 0
          radius: 8
          color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.6)
          border.width: 1
          border.color: Color.popups.border

          Column {
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(6)

            Text {
              text: "Choose Translation Engine:"
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Flow {
              id: engineFlow
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: Model.ENGINES
                delegate: Rectangle {
                  width: engineItemRow.implicitWidth + Style.space(16)
                  height: Style.space(26)
                  radius: 6
                  readonly property bool active: controller && controller.currentEngine === modelData.id
                  color: active ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25)
                                : (itemMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
                                                           : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06))
                  border.width: active ? 1 : 0
                  border.color: Color.accent

                  Row {
                    id: engineItemRow
                    anchors.centerIn: parent
                    spacing: Style.space(4)

                    Text {
                      text: modelData.name
                      color: active ? Color.accent : Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      font.bold: active
                    }
                  }

                  MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (controller) controller.changeEngine(modelData.id)
                      panelRoot.showEnginePicker = false
                    }
                  }
                }
              }
            }
          }
        }

        // ---- DRAWER: LANGUAGE PICKER ---------------------------------------
        Rectangle {
          visible: panelRoot.showLanguagePicker
          width: parent.width
          height: panelRoot.showLanguagePicker ? langFlow.implicitHeight + Style.space(16) : 0
          radius: 8
          color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.6)
          border.width: 1
          border.color: Color.popups.border

          Column {
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(6)

            Text {
              text: "Select Target Language:"
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Flow {
              id: langFlow
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: Model.LANGUAGES
                delegate: Rectangle {
                  width: langItemRow.implicitWidth + Style.space(16)
                  height: Style.space(26)
                  radius: 6
                  readonly property bool active: controller && controller.targetLanguage === modelData.code
                  color: active ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25)
                                : (lMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
                                                        : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06))
                  border.width: active ? 1 : 0
                  border.color: Color.accent

                  Row {
                    id: langItemRow
                    anchors.centerIn: parent
                    spacing: Style.space(4)

                    Text {
                      text: modelData.flag + " " + modelData.name
                      color: active ? Color.accent : Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      font.bold: active
                    }
                  }

                  MouseArea {
                    id: lMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (controller) controller.changeTargetLanguage(modelData.code)
                      panelRoot.showLanguagePicker = false
                    }
                  }
                }
              }
            }
          }
        }

        // ---- DRAWER: SETTINGS ---------------------------------------------
        Rectangle {
          visible: panelRoot.showSettings
          width: parent.width
          height: panelRoot.showSettings ? settingsCol.implicitHeight + Style.space(16) : 0
          radius: 8
          color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.6)
          border.width: 1
          border.color: Color.popups.border

          Column {
            id: settingsCol
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(8)

            Text {
              text: "Engine Settings & Keys"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            // DeepL Key Input
            Column {
              width: parent.width
              spacing: 2
              Text { text: "DeepL Auth Key (for DeepL engine):"; color: Color.muted; font.pixelSize: Style.font.caption }
              Rectangle {
                width: parent.width
                height: Style.space(26)
                radius: 4
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                border.width: 1
                border.color: Color.popups.border
                TextInput {
                  anchors.fill: parent
                  anchors.leftMargin: 6; anchors.rightMargin: 6
                  color: Color.foreground
                  font.pixelSize: Style.font.caption
                  verticalAlignment: TextInput.AlignVCenter
                  text: controller ? controller.settings.deeplApiKey : ""
                  onEditingFinished: if (controller) controller.persistSetting("deeplApiKey", text.trim())
                }
              }
            }

            // LibreTranslate URL
            Column {
              width: parent.width
              spacing: 2
              Text { text: "LibreTranslate Server URL:"; color: Color.muted; font.pixelSize: Style.font.caption }
              Rectangle {
                width: parent.width
                height: Style.space(26)
                radius: 4
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                border.width: 1
                border.color: Color.popups.border
                TextInput {
                  anchors.fill: parent
                  anchors.leftMargin: 6; anchors.rightMargin: 6
                  color: Color.foreground
                  font.pixelSize: Style.font.caption
                  verticalAlignment: TextInput.AlignVCenter
                  text: controller ? controller.settings.libreUrl : ""
                  onEditingFinished: if (controller) controller.persistSetting("libreUrl", text.trim())
                }
              }
            }
          }
        }

        // ---- BODY: SOURCE TEXT --------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(4)

          Row {
            spacing: Style.space(4)
            Text {
              text: "FROM " + (controller ? Model.langDisplay(controller.detectedSource).toUpperCase() : "DETECTED")
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Rectangle {
            width: parent.width
            height: Math.min(Math.max(sourceTextDisplay.implicitHeight + Style.space(12), Style.space(36)), Style.space(90))
            radius: 8
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
            border.width: 1
            border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)

            Flickable {
              anchors.fill: parent
              anchors.margins: Style.space(8)
              contentWidth: width
              contentHeight: sourceTextDisplay.implicitHeight
              clip: true

              TextEdit {
                id: sourceTextDisplay
                width: parent.width
                text: controller ? controller.sourceText : ""
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.8)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                wrapMode: TextEdit.Wrap
                readOnly: false
                selectByMouse: true
                onEditingFinished: {
                  if (controller && text.trim() !== controller.sourceText.trim()) {
                    controller.translateDirect(text.trim())
                  }
                }
              }
            }
          }
        }

        // Divider
        Rectangle {
          width: parent.width
          height: 1
          color: Color.popups.border
        }

        // ---- BODY: TRANSLATED TEXT ----------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(4)

          Row {
            spacing: Style.space(4)
            Text {
              text: "TO " + (controller ? Model.langDisplay(controller.targetLanguage).toUpperCase() : "ENGLISH")
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              visible: controller && !!controller.fallbackNote
              text: "· (" + (controller ? controller.fallbackNote : "") + ")"
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          // Content Box / Loading / Error
          Rectangle {
            width: parent.width
            height: controller && controller.loading ? Style.space(60) :
                    Math.min(Math.max(translatedTextDisplay.implicitHeight + Style.space(14), Style.space(44)), Style.space(180))
            radius: 8
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)
            border.width: 1
            border.color: controller && controller.errorMessage !== "" ? Color.urgent : Color.popups.border

            Behavior on height { NumberAnimation { duration: 100 } }

            // Loading View
            Row {
              visible: controller && controller.loading
              anchors.centerIn: parent
              spacing: Style.space(8)

              Text {
                text: "󰑮"
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.iconSmall || 16
                RotationAnimation on rotation {
                  from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                  running: controller && controller.loading
                }
              }

              Text {
                text: "Translating with " + (controller ? controller.currentEngine.toUpperCase() : "Google") + "..."
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }

            // Error View
            Column {
              visible: controller && !controller.loading && controller.errorMessage !== ""
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                text: "Translation Error"
                color: Color.urgent
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                anchors.horizontalCenter: parent.horizontalCenter
              }

              Text {
                text: controller ? controller.errorMessage : ""
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                width: parent.width - Style.space(16)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
              }
            }

            // Success View
            Flickable {
              visible: controller && !controller.loading && controller.errorMessage === ""
              anchors.fill: parent
              anchors.margins: Style.space(8)
              contentWidth: width
              contentHeight: translatedTextDisplay.implicitHeight
              clip: true

              TextEdit {
                id: translatedTextDisplay
                width: parent.width
                text: controller ? controller.translatedText : ""
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                wrapMode: TextEdit.Wrap
                readOnly: true
                selectByMouse: true
              }
            }
          }
        }

        // ---- ACTION TOOLBAR -----------------------------------------------
        Item {
          width: parent.width
          height: Style.space(32)

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            // Copy Button
            Rectangle {
              height: Style.space(28)
              width: copyRow.implicitWidth + Style.space(20)
              radius: 6
              color: panelRoot.copiedFeedback ? Color.accent
                                              : (copyMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.14)
                                                                         : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08))

              Row {
                id: copyRow
                anchors.centerIn: parent
                spacing: Style.space(5)

                Text {
                  text: panelRoot.copiedFeedback ? "✓" : "󰆏"
                  color: panelRoot.copiedFeedback ? Color.background : Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
                Text {
                  text: panelRoot.copiedFeedback ? "Copied!" : "Copy"
                  color: panelRoot.copiedFeedback ? Color.background : Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }

              MouseArea {
                id: copyMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (controller) {
                    controller.copyTranslation()
                    panelRoot.copiedFeedback = true
                    copyFeedbackTimer.restart()
                  }
                }
              }
            }

            // Replace Button
            Rectangle {
              height: Style.space(28)
              width: replaceRow.implicitWidth + Style.space(20)
              radius: 6
              color: replaceMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.14)
                                                : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)

              Row {
                id: replaceRow
                anchors.centerIn: parent
                spacing: Style.space(5)

                Text {
                  text: "󰛔"
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
                Text {
                  text: "Replace"
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }

              MouseArea {
                id: replaceMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (controller) controller.replaceSelection()
                }
              }
            }

            // Speak / Listen Button
            Rectangle {
              height: Style.space(28)
              width: Style.space(28)
              radius: 6
              color: speakMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.14)
                                              : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)

              Text {
                anchors.centerIn: parent
                text: "󰕾"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: speakMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (controller) controller.speakTranslation()
                }
              }
            }
          }

          // Settings Gear Button
          Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(28)
            width: Style.space(28)
            radius: 6
            color: panelRoot.showSettings ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25)
                                          : (gearMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.14)
                                                                     : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08))

            Text {
              anchors.centerIn: parent
              text: "󰒓"
              color: panelRoot.showSettings ? Color.accent : Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: gearMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                panelRoot.showSettings = !panelRoot.showSettings
                panelRoot.showLanguagePicker = false
                panelRoot.showEnginePicker = false
              }
            }
          }
        }
      }
    }
  }
}
