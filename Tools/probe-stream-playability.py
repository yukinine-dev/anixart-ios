#!/usr/bin/env python3
"""What does a hosting's "direct" URL actually serve, and can AVPlayer play it?

`iframe: false` only says the API gave us a URL instead of a player page. It
says nothing about what is behind that URL, and AVFoundation is picky: it plays
MP4/MOV and HLS, and refuses MKV outright, VP9 and AV1 among others. A stream
that fails those checks shows no picture at all, which is indistinguishable
from a bug in the player.

This finds a release by title, walks its voice-overs and hostings, and for every
distinct episode URL reports what the server says about it -- redirects, status,
content type, size -- plus a verdict on whether AVPlayer stands a chance.

    python3 Tools/probe-stream-playability.py "Киберпанк: Бегущие по краю"
"""

import argparse
import json
import sys
import urllib.error
import urllib.request
from urllib.parse import urlparse

DEFAULT_API = "https://api-s.anixsekai.com"
TIMEOUT = 30
USER_AGENT = "anixart-ios-probe/1.0"
# The Referer the Android app sends, which several hostings check.
REFERER = "https://anixart-app.com"

# What AVFoundation will and will not open.
PLAYABLE_TYPES = ("video/mp4", "video/quicktime", "application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl")
REFUSED_HINTS = ("matroska", "webm", "x-msvideo", "ogg")


def api(path: str, body: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"User-Agent": USER_AGENT}
    if data:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(f"{DEFAULT_API}/{path}", data=data, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            return json.load(response)
    except Exception as error:  # noqa: BLE001 - diagnostics, any failure is information
        print(f"  ! {path}: {error}", file=sys.stderr)
        return None


def inspect(url: str) -> dict:
    """Ask the server about the URL the way a player would: a ranged GET."""
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Referer": REFERER,
            # A player never pulls the whole file to find out what it is.
            "Range": "bytes=0-1023",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            head = response.read(1024)
            return {
                "status": response.status,
                "final_url": response.url,
                "content_type": response.headers.get("Content-Type", "?"),
                "length": response.headers.get("Content-Length", "?"),
                "accept_ranges": response.headers.get("Accept-Ranges", "-"),
                "magic": head[:16].hex(),
                "head": head,
            }
    except urllib.error.HTTPError as error:
        return {"status": error.code, "final_url": url, "content_type": "?", "error": str(error)}
    except Exception as error:  # noqa: BLE001
        return {"status": 0, "final_url": url, "content_type": "?", "error": str(error)}


def verdict(info: dict) -> str:
    if info.get("error") and info.get("status", 0) == 0:
        return f"UNREACHABLE ({info['error']})"
    if info.get("status", 0) not in (200, 206):
        return f"HTTP {info['status']}"

    content_type = (info.get("content_type") or "").lower()
    head = info.get("head") or b""

    # Containers identify themselves in their first bytes, which beats trusting
    # a Content-Type that hostings often set to application/octet-stream.
    if head[:4] == b"\x1aE\xdf\xa3":
        return "MKV/WebM -- AVPlayer cannot open this at all"
    if head[4:8] == b"ftyp":
        brand = head[8:12].decode("latin1", "replace")
        return f"MP4 (brand {brand}) -- playable"
    if head[:7] == b"#EXTM3U":
        return "HLS playlist -- playable"
    if any(hint in content_type for hint in REFUSED_HINTS):
        return f"{content_type} -- AVPlayer refuses this"
    if any(content_type.startswith(t) for t in PLAYABLE_TYPES):
        return f"{content_type} -- probably playable"
    if head[:9] == b"<!DOCTYPE" or head[:5] == b"<html" or "text/html" in content_type:
        return "HTML page, not a stream"
    return f"unknown ({content_type}, magic {info.get('magic')})"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("title", nargs="?", default="Киберпанк: Бегущие по краю")
    parser.add_argument("--episodes", type=int, default=1, help="URLs to inspect per hosting")
    args = parser.parse_args()

    found = api("search/releases/0", {"query": args.title, "searchBy": 0})
    releases = (found or {}).get("content") or []
    if not releases:
        print(f"nothing found for {args.title!r}", file=sys.stderr)
        return 0

    release = releases[0]
    release_id = release["id"]
    print(f"release: {release.get('title_ru')} (id {release_id})\n")

    types = (api(f"episode/{release_id}") or {}).get("types") or []
    for voice in types:
        sources = (api(f"episode/{release_id}/{voice['id']}") or {}).get("sources") or []
        for source in sources:
            episodes = (
                api(f"episode/{release_id}/{voice['id']}/{source['id']}?sort=0") or {}
            ).get("episodes") or []
            direct = [e for e in episodes if not e.get("iframe") and e.get("url")]
            label = f"{voice.get('name')} / {source.get('name')}"

            if not direct:
                print(f"{label}: {len(episodes)} episodes, all player pages")
                continue

            print(f"{label}: {len(direct)} direct of {len(episodes)}")
            for episode in direct[: args.episodes]:
                url = episode["url"]
                info = inspect(url)
                scheme = urlparse(url).scheme
                print(f"    {episode.get('name') or episode.get('position')}: {scheme}://{urlparse(url).netloc}")
                print(f"      url      {url}")
                if info.get("final_url") != url:
                    print(f"      -> {info.get('final_url')}")
                print(f"      type     {info.get('content_type')}  size {info.get('length')}  ranges {info.get('accept_ranges')}")
                print(f"      verdict  {verdict(info)}")
            print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
