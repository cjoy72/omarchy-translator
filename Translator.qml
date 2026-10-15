import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "TranslatorModel.js" as Model

// Translator panel root: Exactly mirrors OmaDrop's geometry and lifecycle pipeline
Item {
  id: root

  // Host injections
  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string moduleId: (manifest && manifest.id) || "cjoy720.translator"

  function scriptPath(name) {
    var url = Qt.resolvedUrl("scripts/" + name).toString()
    return url.indexOf("file://") === 0 ? url.slice("file://".length) : url
  }

  readonly property string homeDir: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (homeDir + "/.local/state")) + "/cjoy720.translator"
  readonly property string settingsPath: stateDir + "/settings.json"

  // Runtime translation state
  property bool opened: false
  property bool loading: false
  property string sourceText: ""
  property string translatedText: ""
  property string detectedSource: "auto"
  property string targetLanguage: "en"
  property string currentEngine: "google"
  property string fallbackNote: ""
  property string errorMessage: ""

  // Settings
  property var settings: Model.DEFAULT_SETTINGS

  function loadSettings(text) {
    var parsed = Model.safeParse(text)
    root.settings = Model.normalizeSettings(parsed)
    root.targetLanguage = root.settings.targetLanguage
    root.currentEngine = root.settings.defaultEngine
  }

  function persistSetting(key, val) {
    var clone = Model.normalizeSettings(root.settings)
    clone[key] = val
    root.settings = clone
    if (key === "targetLanguage") root.targetLanguage = val
    if (key === "defaultEngine") root.currentEngine = val

    settingsWriter.command = ["python3", "-c",
      "import json, os, sys; p = sys.argv[1]; os.makedirs(os.path.dirname(p), exist_ok=True); " +
      "json.dump(json.loads(sys.argv[2]), open(p, 'w'), indent=2)",
      root.settingsPath, JSON.stringify(root.settings)]
    settingsWriter.running = true
  }

  // Load settings on startup
  Process {
    id: settingsReader
    command: ["cat", root.settingsPath]
    stdout: StdioCollector {
      id: settingsOut
      waitForEnd: true
    }
    stderr: StdioCollector {}
    onExited: function(code) {
      if (code === 0 && settingsOut.text) {
        root.loadSettings(settingsOut.text)
      }
    }
  }

  Process {
    id: settingsWriter
    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  // ---- Geometry Pipeline (Identical to OmaDrop) ----------------------------
  property var pendingMonitor: null // { name, x, y, width, height }

  Process {
    id: geomProbe
    stdout: StdioCollector {
      id: geomOut
      waitForEnd: true
    }
    stderr: StdioCollector {}
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyGeometry(geomOut.text)
    }
  }

  function probeAndShow() {
    geomProbe.command = ["bash", "-c",
      'echo "{\\"cursor\\":$(hyprctl cursorpos -j),\\"monitors\\":$(hyprctl monitors -j)}"']
    geomProbe.running = true
  }

  function applyGeometry(text) {
    var data = Model.safeParse(text)
    var monitors = data && Array.isArray(data.monitors) ? data.monitors : []
    var cursor = data && data.cursor ? data.cursor : null
    var monitor = Model.monitorFor(cursor ? cursor.x : -1, cursor ? cursor.y : -1, monitors)
    if (!monitor && monitors.length > 0) monitor = monitors[0]

    root.pendingMonitor = monitor ? {
      name: String(monitor.name || ""),
      x: Number(monitor.x) || 0,
      y: Number(monitor.y) || 0,
      width: Number(monitor.width) || 1280,
      height: Number(monitor.height) || 800
    } : null

    var pos = Model.shelfAnchor(
      monitor, cursor,
      translatorWindow.cardWidth,
      translatorWindow.cardHeightPx > 0 ? translatorWindow.cardHeightPx : translatorWindow.cardEstimatedHeight,
      translatorWindow.edgeMargin
    )

    translatorWindow.anchorX = Math.round(pos.x)
    translatorWindow.anchorY = Math.round(pos.y)
    if (monitor && monitor.name) translatorWindow.useScreen(String(monitor.name))

    root.opened = true
  }

  // Selection Capture Process
  Process {
    id: captureProcess
    stdout: StdioCollector {
      id: captureOut
      waitForEnd: true
    }
    stderr: StdioCollector {}
    onExited: function(code) {
      var res = Model.safeParse(captureOut.text)
      if (res && res.ok && res.text) {
        root.sourceText = res.text
        root.runTranslation(res.text, root.targetLanguage, root.currentEngine)
      } else {
        root.loading = false
      }
    }
  }

  // Translation Process
  Process {
    id: translateProcess
    stdout: StdioCollector {
      id: translateOut
      waitForEnd: true
    }
    stderr: StdioCollector {}
    onExited: function(code) {
      root.loading = false
      var res = Model.safeParse(translateOut.text)
      if (res && res.ok) {
        root.translatedText = res.translatedText || ""
        root.detectedSource = res.source || "auto"
        root.fallbackNote = res.note || ""
        root.errorMessage = ""
      } else if (res && !res.ok) {
        root.errorMessage = res.error || "Translation failed"
      } else {
        root.errorMessage = "Failed to communicate with translation engine"
      }
    }
  }

  function runTranslation(text, target, engine) {
    if (!text || !text.trim()) return
    root.loading = true
    root.errorMessage = ""
    root.fallbackNote = ""

    var cmd = [
      root.scriptPath("translate.py"),
      "--text", text,
      "--target", target || root.targetLanguage,
      "--source", "auto",
      "--engine", engine || root.currentEngine
    ]

    if (root.settings.deeplApiKey) {
      cmd.push("--deepl-key")
      cmd.push(root.settings.deeplApiKey)
    }
    if (root.settings.libreUrl) {
      cmd.push("--libre-url")
      cmd.push(root.settings.libreUrl)
    }
    if (root.settings.lingvaUrl) {
      cmd.push("--lingva-url")
      cmd.push(root.settings.lingvaUrl)
    }

    translateProcess.command = cmd
    translateProcess.running = true
  }

  // Action methods
  function triggerCaptureAndTranslate() {
    root.probeAndShow()
    root.loading = true
    root.errorMessage = ""
    captureProcess.command = [root.scriptPath("capture-selection.sh")]
    captureProcess.running = true
  }

  function translateDirect(text) {
    root.sourceText = text
    runTranslation(text, root.targetLanguage, root.currentEngine)
  }

  function changeTargetLanguage(lang) {
    root.targetLanguage = lang
    persistSetting("targetLanguage", lang)
    if (root.sourceText) {
      runTranslation(root.sourceText, lang, root.currentEngine)
    }
  }

  function changeEngine(engine) {
    root.currentEngine = engine
    persistSetting("defaultEngine", engine)
    if (root.sourceText) {
      runTranslation(root.sourceText, root.targetLanguage, engine)
    }
  }

  function swapLanguages() {
    var oldTarget = root.targetLanguage
    var oldSource = root.detectedSource && root.detectedSource !== "auto" ? root.detectedSource : "en"
    var oldTranslated = root.translatedText

    root.targetLanguage = oldSource
    if (oldTranslated) {
      root.sourceText = oldTranslated
      runTranslation(oldTranslated, oldSource, root.currentEngine)
    }
  }

  // Copier
  Process {
    id: textCopier
    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  function copyTranslation() {
    if (!root.translatedText) return
    textCopier.command = ["wl-copy", root.translatedText]
    textCopier.running = true
  }

  // Replacer
  Process {
    id: textReplacer
    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  function replaceSelection() {
    if (!root.translatedText) return
    root.dismiss()
    textReplacer.command = ["bash", "-c",
      'printf "%s" "$1" | wl-copy && sleep 0.05 && wtype -M ctrl v -m ctrl',
      "replacer", root.translatedText]
    textReplacer.running = true
  }

  // Speaker
  Process {
    id: speechProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  function speakTranslation() {
    if (!root.translatedText) return
    speechProcess.command = ["bash", "-c",
      'if command -v /home/cjoy720/.local/bin/say >/dev/null 2>&1; then /home/cjoy720/.local/bin/say "$1" 2>/dev/null || true; fi',
      "speaker", root.translatedText]
    speechProcess.running = true
  }

  function open() {
    root.probeAndShow()
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(root.moduleId)
    else root.close()
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.triggerCaptureAndTranslate()
  }

  // ---- IPC HANDLER --------------------------------------------------------
  IpcHandler {
    target: "translator"

    function ping(): string { return "pong" }
    function translate(): void { root.triggerCaptureAndTranslate() }
    function capture(): void { root.triggerCaptureAndTranslate() }
    function open(): void { root.open() }
    function close(): void { root.dismiss() }
    function toggle(): void { root.toggle() }

    function translateText(text: string, targetLang: string, engine: string): void {
      if (targetLang) root.targetLanguage = targetLang
      if (engine) root.currentEngine = engine
      root.open()
      root.translateDirect(text)
    }

    function setLanguage(lang: string): void {
      root.changeTargetLanguage(lang)
    }

    function setEngine(engine: string): void {
      root.changeEngine(engine)
    }

    function status(): string {
      return JSON.stringify({
        opened: root.opened,
        loading: root.loading,
        currentEngine: root.currentEngine,
        targetLanguage: root.targetLanguage,
        detectedSource: root.detectedSource,
        sourceLength: root.sourceText.length,
        hasTranslation: !!root.translatedText,
        pendingMonitor: root.pendingMonitor,
        anchorX: translatorWindow.anchorX,
        anchorY: translatorWindow.anchorY
      })
    }
  }

  Component.onCompleted: {
    settingsReader.running = true
  }

  // Floating Window Component
  TranslatorWindow {
    id: translatorWindow
    controller: root
    opened: root.opened
  }
}
