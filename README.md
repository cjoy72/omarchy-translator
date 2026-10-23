# Omarchy Translator Plugin (`cjoy720.translator`)

A sleek, modern floating translator plugin for Omarchy / Hyprland. Like **OmaDrop**, it floats right at your cursor position whenever summoned.

## Features

- 🎯 **Cursor-Floating Window**: Floats directly where your cursor is positioned, with intelligent edge-clamping so it never clips off-screen.
- ✥ **Draggable**: Grab the header or any card background space to smoothly reposition the card.
- ⚡ **Multi-Engine Support**: Choose your preferred translation engine anytime:
  - **Google Translate**: Instant, free, reliable, auto-detects source language.
  - **MyMemory**: Free collaborative translation memory API (100+ languages).
  - **DeepL**: Industry-leading quality (Free or Pro auth key configurable).
  - **LibreTranslate**: Open-source, private (custom server URL & key supported).
  - **Lingva**: Privacy-respecting Google frontend.
- 🌐 **Instant Language Switching**: Click the target language badge to open the visual language picker and translate to any language with 1 click.
- 󰛔 **Replace Selection**: Click "Replace" to paste the translation directly over your selected text.
- 󰆏 **One-Click Copy**: Copy translated text to your clipboard with instant animated confirmation.
- 󰕾 **Speech / Audio**: Listen to the source or translated text via Google TTS and the local `mpv` player.
- ⌨️ **Keyboard Friendly**: Press `Esc` anytime to dismiss.
- 📊 **Status Bar Widget**: Shows an icon on your top bar with the active target language badge (e.g. `ES`).

---

## Installation

You can install this plugin directly via the Omarchy CLI:

```bash
omarchy plugin add https://github.com/cjoy72/omarchy-translator.git --enable
```

Or add it manually:
1. Clone this repository into your Omarchy plugins directory:
   ```bash
   git clone https://github.com/cjoy72/omarchy-translator.git ~/.config/omarchy/plugins/cjoy720.translator
   ```
2. Rescan and enable the plugin:
   ```bash
   omarchy-shell shell rescanPlugins
   omarchy plugin enable cjoy720.translator
   ```

### Recommended Keybinding

To bind the translator to <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>T</kbd>, add this line to your `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + T", "Translate Selection", "omarchy-shell translator translate")
```

---

## Removal

To uninstall the plugin:

```bash
omarchy plugin remove cjoy720.translator
```

---

## Keybinding & Usage

Select any text with your mouse or keyboard, then press:

```
SUPER + CTRL + T
```

The translator will immediately capture the selected text, open right at your cursor, and display the translation in your chosen target language.

You can also run it via terminal or custom shortcuts:
```bash
omarchy-shell translator translate
```

---

## Switching Language & Engine

You can switch engines or languages directly from the floating popup:
1. **Engine**: Click the `[ GOOGLE ▾ ]` pill in the header to switch between Google, MyMemory, DeepL, LibreTranslate, and Lingva.
2. **Target Language**: Click the language badge `[ 🇪🇸 Spanish ▾ ]` to open the quick language grid.
3. **Swap Languages**: Click `󰁯` to swap the detected source language and target language.
4. **Settings**: Click `󰒓` to configure your DeepL API key or custom LibreTranslate/Lingva server URLs.

Preferences are automatically saved in `~/.local/state/cjoy720.translator/settings.json`.

---

## Dependencies

The plugin uses standard tools pre-installed on Omarchy:
- `python3` (built-in standard library `urllib`, `json`, `socket`)
- `wl-clipboard` (`wl-paste`, `wl-copy`)
- `wtype` or `ydotool` (for text replacement synthesis)
- `mpv` (for speech playback)

Speech playback uses Google Translate's public TTS endpoint, so an internet connection is required. The plugin does not use a user-specific filesystem path; it resolves its own scripts from the installed plugin directory.

---

## IPC Commands

The plugin responds to Quickshell IPC via `omarchy-shell`:

```bash
omarchy-shell translator translate               # Capture selection and open floating translation at cursor
omarchy-shell translator open                    # Open floating window at cursor
omarchy-shell translator close                   # Close floating window
omarchy-shell translator toggle                  # Toggle floating window
omarchy-shell translator translateText "<text>" "<target_lang>" "<engine>"  # Translate explicit text
omarchy-shell translator setLanguage "<lang>"    # Change target language (e.g. es, fr, de, it, ja)
omarchy-shell translator setEngine "<engine>"    # Change engine (google, mymemory, deepl, libretranslate, lingva)
omarchy-shell translator status                  # Output JSON status
```

---

## File Structure

```
~/.config/omarchy/plugins/cjoy720.translator/
├── manifest.json            # Plugin manifest (bar-widget + panel)
├── Translator.qml           # Panel root & IPC controller
├── TranslatorWindow.qml     # Layer-shell floating cursor card
├── BarWidget.qml            # Status bar widget
├── TranslatorModel.js       # Languages, engines, geometry calculation
├── LICENSE                  # MIT License
├── README.md                # Documentation
└── scripts/
    ├── capture-selection.sh # Selection capture pipeline
    ├── cursor-stream        # Hyprland socket cursor streamer for smooth window dragging
    └── translate.py         # Multi-engine translation backend
```

---

## License

[MIT](LICENSE) © 2026 cjoy720
