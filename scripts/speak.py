#!/usr/bin/env python3
"""Read text aloud through Google TTS and the local mpv player."""

import argparse
import re
import subprocess
import sys
import urllib.parse
import urllib.request


def chunks(text, limit=180):
    """按标点或空格分段，避免超过语音接口的长度限制。"""
    text = re.sub(r"\s+", " ", text).strip()
    while text:
        end = min(len(text), limit)
        if len(text) > limit:
            boundaries = list(re.finditer(r"[。！？；.!?;\s]", text[:limit]))
            if boundaries:
                end = boundaries[-1].end()
        yield text[:end]
        text = text[end:].lstrip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--text", required=True)
    parser.add_argument("--language", required=True)
    args = parser.parse_args()
    language = "zh-CN" if args.language == "zh" else args.language
    if not args.text.strip():
        return
    if language == "auto":
        raise ValueError("无法确定发音语言，请先完成翻译")
    for part in chunks(args.text):
        query = urllib.parse.urlencode({
            "ie": "UTF-8", "client": "tw-ob", "tl": language, "q": part,
        })
        request = urllib.request.Request(
            "https://translate.google.com/translate_tts?" + query,
            headers={"User-Agent": "Mozilla/5.0"},
        )
        with urllib.request.urlopen(request, timeout=15) as response:
            if not response.headers.get("Content-Type", "").startswith("audio/"):
                raise ValueError("语音服务没有返回音频")
            audio = response.read(2 * 1024 * 1024)
        subprocess.run(
            ["mpv", "--no-config", "--no-video", "--audio-display=no",
             "--really-quiet", "--", "-"],
            input=audio, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
            check=True, timeout=90,
        )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("发音失败，请检查网络和音频输出。" + type(exc).__name__, file=sys.stderr)
        sys.exit(1)
