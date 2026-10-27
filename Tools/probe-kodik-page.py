#!/usr/bin/env python3
"""What is actually inside a Kodik player page?

The APK's KodikParser fetches that page and pulls four quality URLs out of it
with four regexes. The regexes themselves are behind LSParanoid, the string
obfuscator this APK applies to every literal in every class, so they cannot be
read from the decompiled source -- but the page can be read directly, which is
better anyway: a regex written against today's page cannot be stale.

This reports what the page contains without asserting anything about it: its
status, what scripts it loads, and every video-looking URL in it.

    python3 Tools/probe-kodik-page.py "Киберпанк: Бегущие по краю"
"""

import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

ANIXART_API = "https://api-s.anixsekai.com"
USER_AGENT = "anixart-ios-probe/1.0"
# The Referer the Android app sends.
REFERER = "https://anixart-app.com"
TIMEOUT = 25

INTERESTING = [
    (".m3u8", r".{60}\.m3u8.{40}"),
    (".mp4", r".{60}\.mp4.{40}"),
    ("KodikInterface", r".{40}KodikInterface.{60}"),
    ("advertEnded", r".{40}advertEnded.{60}"),
    ("videoInfo", r".{20}videoInfo.{80}"),
    ("urlParams", r".{20}urlParams.{80}"),
    ("/ftor", r".{40}/ftor.{60}"),
]


def anixart(path: str, body: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"User-Agent": USER_AGENT}
    if data:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(f"{ANIXART_API}/{path}", data=data, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            return json.load(response)
    except Exception as error:  # noqa: BLE001 - diagnostics
        print(f"  ! {path}: {error}", file=sys.stderr)
        return None


def kodik_url(title: str) -> str | None:
    found = anixart("search/releases/0", {"query": title, "searchBy": 0})
    releases = (found or {}).get("content") or []
    if not releases:
        print(f"  nothing on Anixart for {title!r}")
        return None
    release = releases[0]
    print(f"  anixart: {release.get('title_ru')!r} id {release['id']}")

    for voice in (anixart(f"episode/{release['id']}") or {}).get("types") or []:
        for source in (anixart(f"episode/{release['id']}/{voice['id']}") or {}).get("sources") or []:
            episodes = (
                anixart(f"episode/{release['id']}/{voice['id']}/{source['id']}?sort=0") or {}
            ).get("episodes") or []
            for episode in episodes:
                url = episode.get("url") or ""
                if "kodik" in url or "aniqit" in url:
                    print(f"  via {voice.get('name')} / {source.get('name')}")
                    return url.split('"')[0]
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("title", nargs="?", default="Киберпанк: Бегущие по краю")
    args = parser.parse_args()

    url = kodik_url(args.title)
    if not url:
        print("  no Kodik episode found")
        return 0
    print(f"  page: {url}")

    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Referer": REFERER})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            status = response.status
            content_type = response.headers.get("Content-Type", "?")
            body = response.read(400_000).decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        print(f"  page: HTTP {error.code} {error.headers.get('Content-Type', '?') if error.headers else ''}")
        return 0
    except Exception as error:  # noqa: BLE001
        print(f"  page unreachable: {error}")
        return 0

    print(f"  page: HTTP {status} {content_type} {len(body)} chars")

    scripts = re.findall(r'<script[^>]+src=["\']([^"\']+)', body)
    print(f"  {len(scripts)} script sources:")
    for src in scripts[:12]:
        print(f"    {src}")

    for label, pattern in INTERESTING:
        hits = re.findall(pattern, body, re.S)
        print(f"  {label}: {len(hits)} occurrence(s)")
        for hit in hits[:3]:
            print(f"    …{hit.strip()[:160]}…")

    return 0


if __name__ == "__main__":
    sys.exit(main())
