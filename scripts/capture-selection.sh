#!/usr/bin/env bash
# capture-selection.sh - Captures selected text in Wayland / Hyprland
# Prints a single JSON line:
# {"ok": true, "text": "...", "method": "primary"|"clipboard"|"synthesized"}
# or {"ok": false, "text": "", "reason": "no-selection"}

set -uo pipefail

finish() {
  local ok="$1"
  local reason="$2"
  local method="$3"
  local text="$4"
  RAW_TEXT="$text" python3 - "$ok" "$reason" "$method" <<'PY'
import json, os, sys

ok = sys.argv[1] == "true"
reason = sys.argv[2]
method = sys.argv[3]
raw_text = os.environ.get("RAW_TEXT", "")

trimmed = raw_text.strip()
if not trimmed:
    ok = False
    reason = reason or "no-selection"

print(json.dumps({
    "ok": bool(ok and trimmed),
    "text": trimmed,
    "method": method,
    "reason": reason
}, ensure_ascii=False))
PY
}

# 1. Try reading the Primary selection directly (fastest on Linux / Wayland)
primary_text="$(wl-paste --primary 2>/dev/null || true)"
if [[ -n "${primary_text//[[:space:]]/}" ]]; then
  finish "true" "" "primary" "$primary_text"
  exit 0
fi

# 2. Check focused window class before simulating key events
active_class="$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // ""' 2>/dev/null || echo "")"
active_class_lower="${active_class,,}"

case "$active_class_lower" in
  *kitty*|*alacritty*|*foot*|*ghostty*|*wezterm*)
    # Inside terminal: do not synthesize Ctrl+C to avoid SIGINT
    clip_text="$(wl-paste 2>/dev/null || true)"
    if [[ -n "${clip_text//[[:space:]]/}" ]]; then
      finish "true" "" "clipboard" "$clip_text"
    else
      finish "false" "no-selection" "none" ""
    fi
    exit 0
    ;;
esac

# 3. Non-terminal: snapshot clipboard, synthesize copy, read result
prev_clip="$(wl-paste 2>/dev/null || true)"
wl-copy --clear >/dev/null 2>&1 || true

# Ydotool socket setup
YDOTOOL_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/.ydotool_socket"
if [ ! -S "$YDOTOOL_SOCKET" ]; then
  YDOTOOL_SOCKET="/run/user/1000/.ydotool_socket"
fi

if [ -S "$YDOTOOL_SOCKET" ]; then
  # 29=Ctrl, 46=c
  YDOTOOL_SOCKET="$YDOTOOL_SOCKET" ydotool key -d 25 29:1 46:1 46:0 29:0 >/dev/null 2>&1 || true
elif command -v wtype >/dev/null 2>&1; then
  wtype -M ctrl -k c -m ctrl >/dev/null 2>&1 || true
fi

sleep 0.05
new_clip="$(wl-paste 2>/dev/null || true)"

if [[ -n "${new_clip//[[:space:]]/}" ]]; then
  finish "true" "" "synthesized" "$new_clip"
  exit 0
fi

# 4. Fallback to previous clipboard if nothing was selected
if [[ -n "$prev_clip" ]]; then
  printf "%s" "$prev_clip" | wl-copy >/dev/null 2>&1 || true
  # If previous clipboard had non-empty text, use it as fallback
  if [[ -n "${prev_clip//[[:space:]]/}" ]]; then
    finish "true" "" "clipboard" "$prev_clip"
    exit 0
  fi
fi

finish "false" "no-selection" "none" ""
