#!/usr/bin/env python3
"""
Multi-engine translation script for Omarchy Translator Plugin.
Supports:
  - Google Translate (Chrome Extension dict endpoint & web fallback)
  - MyMemory API (translated.net)
  - DeepL API (Free / Pro with user key)
  - LibreTranslate (Custom / public server)
  - Lingva Translate (Privacy Google proxy)
"""

import sys
import os
import json
import argparse
import urllib.request
import urllib.parse
import urllib.error

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

def translate_google(text: str, target: str, source: str = "auto") -> tuple[str, str]:
    """Translate using Google's Chrome extension endpoint."""
    src = "auto" if not source or source == "auto" else source
    params = urllib.parse.urlencode({
        "client": "dict-chrome-ex",
        "sl": src,
        "tl": target,
        "q": text
    })
    url = f"https://clients5.google.com/translate_a/t?{params}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    
    with urllib.request.urlopen(req, timeout=8) as response:
        raw = response.read().decode("utf-8")
        data = json.loads(raw)
        
        # Expected structure: [["translated text", "detected_lang"]]
        # Or array of chunks: [["chunk 1", "en"], ["chunk 2", "en"]]
        if isinstance(data, list) and len(data) > 0:
            if isinstance(data[0], list):
                chunks = []
                detected = src
                for item in data:
                    if isinstance(item, list) and len(item) > 0:
                        chunks.append(str(item[0]))
                        if len(item) > 1 and item[1]:
                            detected = str(item[1])
                return "".join(chunks), detected
            elif isinstance(data[0], str):
                return str(data[0]), src
        return str(data), src

def translate_mymemory(text: str, target: str, source: str = "auto") -> tuple[str, str]:
    """Translate using MyMemory API."""
    src = "autodetect" if not source or source == "auto" else source
    langpair = f"{src}|{target}"
    params = urllib.parse.urlencode({
        "q": text,
        "langpair": langpair
    })
    url = f"https://api.mymemory.translated.net/get?{params}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    
    with urllib.request.urlopen(req, timeout=8) as response:
        data = json.loads(response.read().decode("utf-8"))
        res_data = data.get("responseData", {})
        translated = res_data.get("translatedText", "")
        
        # Detected source language often in matches
        detected = source
        matches = data.get("matches", [])
        if matches and isinstance(matches, list) and len(matches) > 0:
            m_src = matches[0].get("source", "")
            if m_src:
                detected = m_src.split("-")[0].lower()
                
        if not translated:
            raise ValueError(data.get("responseDetails", "No translation returned from MyMemory"))
        return translated, detected

def translate_deepl(text: str, target: str, source: str = "auto", api_key: str = "") -> tuple[str, str]:
    """Translate using DeepL API."""
    if not api_key:
        raise ValueError("DeepL requires an API key. Please configure your DeepL Auth Key in Translator Settings.")
    
    # Check if free or pro endpoint
    endpoint = "https://api-free.deepl.com/v2/translate" if api_key.endswith(":fx") else "https://api.deepl.com/v2/translate"
    
    # DeepL language codes are uppercase (e.g. EN-US, EN-GB, ES, DE, FR)
    tgt = target.upper()
    if tgt == "EN":
        tgt = "EN-US"
    elif tgt == "PT":
        tgt = "PT-PT"
        
    payload = {
        "text": [text],
        "target_lang": tgt
    }
    if source and source != "auto":
        payload["source_lang"] = source.upper()
        
    data_bytes = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        endpoint,
        data=data_bytes,
        headers={
            "User-Agent": USER_AGENT,
            "Authorization": f"DeepL-Auth-Key {api_key}",
            "Content-Type": "application/json"
        }
    )
    with urllib.request.urlopen(req, timeout=10) as response:
        res = json.loads(response.read().decode("utf-8"))
        translations = res.get("translations", [])
        if translations:
            item = translations[0]
            return item.get("text", ""), item.get("detected_source_language", source).lower()
        raise ValueError("No translation returned from DeepL")

def translate_libretranslate(text: str, target: str, source: str = "auto", base_url: str = "", api_key: str = "") -> tuple[str, str]:
    """Translate using LibreTranslate instance."""
    url = (base_url or "https://translate.terraprint.co").rstrip("/") + "/translate"
    payload = {
        "q": text,
        "source": "auto" if not source else source,
        "target": target,
        "format": "text"
    }
    if api_key:
        payload["api_key"] = api_key
        
    data_bytes = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data_bytes,
        headers={
            "User-Agent": USER_AGENT,
            "Content-Type": "application/json"
        }
    )
    with urllib.request.urlopen(req, timeout=10) as response:
        res = json.loads(response.read().decode("utf-8"))
        if "error" in res:
            raise ValueError(res["error"])
        translated = res.get("translatedText", "")
        detected = res.get("detectedLanguage", {}).get("language", source)
        return translated, detected

def translate_lingva(text: str, target: str, source: str = "auto", base_url: str = "") -> tuple[str, str]:
    """Translate using Lingva instance."""
    base = (base_url or "https://lingva.ml").rstrip("/")
    src = "auto" if not source or source == "auto" else source
    encoded_text = urllib.parse.quote(text, safe="")
    url = f"{base}/api/v1/{src}/{target}/{encoded_text}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=10) as response:
        res = json.loads(response.read().decode("utf-8"))
        translated = res.get("translation", "")
        detected = res.get("info", {}).get("detectedSource", source)
        if not translated:
            raise ValueError("No translation returned from Lingva")
        return translated, detected

def main():
    parser = argparse.ArgumentParser(description="Multi-engine translator CLI")
    parser.add_argument("--text", "-t", default=None, help="Text to translate (or stdin if omitted)")
    parser.add_argument("--target", default="en", help="Target language code (e.g. en, es, fr, de)")
    parser.add_argument("--source", default="auto", help="Source language code (default auto)")
    parser.add_argument("--engine", default="google", help="Engine: google, mymemory, deepl, libretranslate, lingva")
    parser.add_argument("--deepl-key", default="", help="DeepL API auth key")
    parser.add_argument("--libre-url", default="", help="LibreTranslate server URL")
    parser.add_argument("--lingva-url", default="", help="Lingva server URL")
    
    args = parser.parse_args()
    
    text = args.text
    if text is None or text == "-":
        if not sys.stdin.isatty():
            text = sys.stdin.read()
        else:
            text = ""
            
    text = (text or "").strip()
    if not text:
        print(json.dumps({
            "ok": False,
            "error": "No text provided to translate",
            "sourceText": "",
            "translatedText": "",
            "source": args.source,
            "target": args.target,
            "engine": args.engine
        }))
        sys.exit(0)
        
    engine = args.engine.lower()
    try:
        if engine == "google":
            translated, detected = translate_google(text, args.target, args.source)
        elif engine == "mymemory":
            translated, detected = translate_mymemory(text, args.target, args.source)
        elif engine == "deepl":
            translated, detected = translate_deepl(text, args.target, args.source, args.deepl_key)
        elif engine == "libretranslate":
            translated, detected = translate_libretranslate(text, args.target, args.source, args.libre_url)
        elif engine == "lingva":
            translated, detected = translate_lingva(text, args.target, args.source, args.lingva_url)
        else:
            # Fallback to google
            translated, detected = translate_google(text, args.target, args.source)
            engine = "google"
            
        print(json.dumps({
            "ok": True,
            "sourceText": text,
            "translatedText": translated,
            "source": detected or args.source,
            "target": args.target,
            "engine": engine
        }, ensure_ascii=False))
    except Exception as exc:
        # If preferred engine fails, try google as graceful fallback if engine wasn't google
        fallback_err = str(exc)
        if engine != "google":
            try:
                translated, detected = translate_google(text, args.target, args.source)
                print(json.dumps({
                    "ok": True,
                    "sourceText": text,
                    "translatedText": translated,
                    "source": detected or args.source,
                    "target": args.target,
                    "engine": "google",
                    "note": f"{engine.capitalize()} failed ({fallback_err}), fell back to Google."
                }, ensure_ascii=False))
                sys.exit(0)
            except Exception:
                pass
                
        print(json.dumps({
            "ok": False,
            "error": fallback_err,
            "sourceText": text,
            "translatedText": "",
            "source": args.source,
            "target": args.target,
            "engine": engine
        }, ensure_ascii=False))
        sys.exit(0)

if __name__ == "__main__":
    main()
