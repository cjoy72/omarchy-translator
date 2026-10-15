// TranslatorModel.js - Core state, settings, and positioning logic for Translator plugin

var LANGUAGES = [
  { code: "en", name: "English", flag: "🇺🇸" },
  { code: "es", name: "Spanish", flag: "🇪🇸" },
  { code: "fr", name: "French", flag: "🇫🇷" },
  { code: "de", name: "German", flag: "🇩🇪" },
  { code: "it", name: "Italian", flag: "🇮🇹" },
  { code: "pt", name: "Portuguese", flag: "🇵🇹" },
  { code: "ru", name: "Russian", flag: "🇷🇺" },
  { code: "zh", name: "Chinese", flag: "🇨🇳" },
  { code: "ja", name: "Japanese", flag: "🇯🇵" },
  { code: "ko", name: "Korean", flag: "🇰🇷" },
  { code: "ar", name: "Arabic", flag: "🇸🇦" },
  { code: "hi", name: "Hindi", flag: "🇮🇳" },
  { code: "nl", name: "Dutch", flag: "🇳🇱" },
  { code: "pl", name: "Polish", flag: "🇵🇱" },
  { code: "tr", name: "Turkish", flag: "🇹🇷" },
  { code: "uk", name: "Ukrainian", flag: "🇺🇦" },
  { code: "vi", name: "Vietnamese", flag: "🇻🇳" },
  { code: "sv", name: "Swedish", flag: "🇸🇪" }
]

var ENGINES = [
  { id: "google", name: "Google", desc: "Fast & free, auto-detects source" },
  { id: "mymemory", name: "MyMemory", desc: "Free collaborative translation memory" },
  { id: "deepl", name: "DeepL", desc: "High quality (API key required)" },
  { id: "libretranslate", name: "LibreTranslate", desc: "Open-source & private" },
  { id: "lingva", name: "Lingva", desc: "Privacy Google proxy" }
]

var DEFAULT_SETTINGS = {
  targetLanguage: "en",
  defaultEngine: "google",
  autoCopy: false,
  cardWidth: 450,
  deeplApiKey: "",
  libreUrl: "https://translate.terraprint.co",
  lingvaUrl: "https://lingva.ml"
}

function safeParse(text) {
  try {
    var raw = String(text === undefined || text === null ? "" : text).trim()
    if (!raw) return null
    var value = JSON.parse(raw)
    return (value && typeof value === "object") ? value : null
  } catch (e) {
    return null
  }
}

function normalizeSettings(raw) {
  var s = raw && typeof raw === "object" ? raw : {}
  return {
    targetLanguage: typeof s.targetLanguage === "string" && s.targetLanguage ? s.targetLanguage : DEFAULT_SETTINGS.targetLanguage,
    defaultEngine: typeof s.defaultEngine === "string" && s.defaultEngine ? s.defaultEngine : DEFAULT_SETTINGS.defaultEngine,
    autoCopy: !!s.autoCopy,
    cardWidth: Number(s.cardWidth) || DEFAULT_SETTINGS.cardWidth,
    deeplApiKey: typeof s.deeplApiKey === "string" ? s.deeplApiKey : "",
    libreUrl: typeof s.libreUrl === "string" && s.libreUrl ? s.libreUrl : DEFAULT_SETTINGS.libreUrl,
    lingvaUrl: typeof s.lingvaUrl === "string" && s.lingvaUrl ? s.lingvaUrl : DEFAULT_SETTINGS.lingvaUrl
  }
}

function langByCode(code) {
  if (!code) return { code: "auto", name: "Auto Detect", flag: "🌐" }
  var clean = String(code).toLowerCase().split("-")[0]
  for (var i = 0; i < LANGUAGES.length; i++) {
    if (LANGUAGES[i].code === clean || LANGUAGES[i].code === code.toLowerCase()) {
      return LANGUAGES[i]
    }
  }
  return { code: code, name: code.toUpperCase(), flag: "🌐" }
}

function langDisplay(code) {
  var item = langByCode(code)
  return item.flag + " " + item.name
}

function engineById(id) {
  for (var i = 0; i < ENGINES.length; i++) {
    if (ENGINES[i].id === id) return ENGINES[i]
  }
  return ENGINES[0]
}

function monitorFor(gx, gy, monitors) {
  if (!Array.isArray(monitors)) return null
  for (var i = 0; i < monitors.length; i++) {
    var m = monitors[i]
    if (!m || typeof m !== "object") continue
    var mx = Number(m.x) || 0
    var my = Number(m.y) || 0
    var mw = Number(m.width) || 0
    var mh = Number(m.height) || 0
    if (mw <= 0 || mh <= 0) continue
    if (gx >= mx && gx < mx + mw && gy >= my && gy < my + mh) return m
  }
  return null
}

// Exactly like OmaDrop's shelfAnchor: places the card right under the cursor
function shelfAnchor(monitor, cursor, cardWidth, cardHeight, margin) {
  var mx = monitor ? (Number(monitor.x) || 0) : 0
  var my = monitor ? (Number(monitor.y) || 0) : 0
  var mw = monitor ? (Number(monitor.width) || 1280) : 1280
  var mh = monitor ? (Number(monitor.height) || 800) : 800
  var w = Number(cardWidth) || 450
  var h = Number(cardHeight) || 220
  var pad = Number(margin) || 10

  function clampLocal(x, y) {
    return {
      x: Math.min(Math.max(pad, x), Math.max(pad, mw - w - pad)),
      y: Math.min(Math.max(pad, y), Math.max(pad, mh - h - pad))
    }
  }

  var gx = cursor ? (Number(cursor.x) || 0) : mx + mw / 2
  var gy = cursor ? (Number(cursor.y) || 0) : my + mh / 2
  var lx = gx - mx
  var ly = gy - my

  // OmaDrop standard anchor: cursor at 35% from left and 30% from top
  return clampLocal(lx - w * 0.35, ly - h * 0.30)
}
