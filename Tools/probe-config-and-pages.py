#!/usr/bin/env python3
"""Two questions at once, both measured.

First: where is the Kodik wrapper? `KodikAdActivity` reads its base URL from
`Prefs`, which the app fills from the server's own config, so the server is the
place to look. Guessing paths on `anixart-app.com` was wrong -- every one
returned the same 183083-character catch-all -- so this dumps what `config/*`
actually contains instead.

Second: Sibnet and SovetRomantica need no wrapper at all. The APK has a parser
for each, both of the same "fetch the page, take the URL out of it" shape, and
both hostings appear in the catalogue. This reports what their pages contain so
those parsers can be written against measured content.

    python3 Tools/probe-config-and-pages.py
"""

import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

ANIXART_API = "https://api-s.anixsekai.com"
USER_AGENT = "anixart-ios-probe/1.0"
REFERER = "https://anixart-app.com"
TIMEOUT = 25


def say(*args):
    print("cfg|", *args)


def get(url: str, headers: dict | None = None, limit: int = 400_000):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **(headers or {})})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            return response.status, response.headers.get("Content-Type", "?"), response.read(limit)
    except urllib.error.HTTPError as error:
        return error.code, "?", b""
    except Exception as error:  # noqa: BLE001 - diagnostics
        say(f"! {url}: {error}")
        return 0, "?", b""


def anixart(path: str, body: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"User-Agent": USER_AGENT}
    if data:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(f"{ANIXART_API}/{path}", data=data, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            return json.load(response)
    except Exception as error:  # noqa: BLE001
        say(f"! {path}: {error}")
        return None


def dump_config() -> None:
    """Every field of every config endpoint, so a URL cannot hide in one."""
    for path in ("config/urls", "config/toggles", "config/urls?version=26101718"):
        data = anixart(path)
        if data is None:
            continue
        say(f"--- {path}")
        for key, value in sorted((data or {}).items()):
            shown = json.dumps(value, ensure_ascii=False)
            if len(shown) > 220:
                shown = shown[:220] + "…"
            say(f"    {key} = {shown}")
            # A wrapper base would look like a URL ending in a parameter.
            if isinstance(value, str) and ("http" in value or "url=" in value):
                say(f"    ^^ URL-shaped: {key}")


def episode_url(title: str, marker: str) -> str | None:
    found = anixart("search/releases/0", {"query": title, "searchBy": 0})
    releases = (found or {}).get("content") or []
    if not releases:
        return None
    release = releases[0]
    for voice in (anixart(f"episode/{release['id']}") or {}).get("types") or []:
        for source in (anixart(f"episode/{release['id']}/{voice['id']}") or {}).get("sources") or []:
            episodes = (
                anixart(f"episode/{release['id']}/{voice['id']}/{source['id']}?sort=0") or {}
            ).get("episodes") or []
            for episode in episodes:
                url = (episode.get("url") or "").split('"')[0]
                if marker in url:
                    say(f"    via {voice.get('name')} / {source.get('name')}")
                    return url
    return None


def inspect_page(label: str, url: str) -> None:
    say(f"--- {label}: {url}")
    status, content_type, body = get(url, {"Referer": REFERER})
    say(f"    HTTP {status} {content_type} {len(body)} bytes")
    if not body:
        return
    text = body.decode("utf-8", "replace")

    for name, pattern in [
        (".mp4", r"[^\s\"'<>]{0,80}\.mp4[^\s\"'<>]{0,40}"),
        (".m3u8", r"[^\s\"'<>]{0,80}\.m3u8[^\s\"'<>]{0,40}"),
        ("video/", r"[^\s\"'<>]{0,60}/video/[^\s\"'<>]{0,40}"),
        ("player", r".{0,40}player.{0,40}"),
    ]:
        hits = re.findall(pattern, text)
        say(f"    {name}: {len(hits)}")
        for hit in hits[:3]:
            say(f"      {hit.strip()[:150]}")


def main() -> int:
    dump_config()

    for label, title, marker in [
        ("sibnet", "Киберпанк: Бегущие по краю", "sibnet"),
        ("sovetromantica", "Ванпанчмен", "sovetromantica"),
    ]:
        url = episode_url(title, marker)
        if url:
            inspect_page(label, url)
        else:
            say(f"--- {label}: no episode in the catalogue sample")

    return 0


if __name__ == "__main__":
    sys.exit(main())
