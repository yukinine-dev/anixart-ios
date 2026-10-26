#!/usr/bin/env python3
"""Does AniLibria's own public API hand over a real stream?

Anixart gives no playable URLs: every hosting serves its own player page, so
the built-in player has nothing to open. The question is whether a source with
a documented public API can fill that gap without scraping anyone's player.

AniLibria publishes one, and it returns HLS playlists per episode and quality
directly. This checks that against a title, then fetches the first bytes of the
playlist the way a player would, so the answer is a verdict and not a hope.

    python3 Tools/probe-anilibria.py "Киберпанк: Бегущие по краю"
"""

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

USER_AGENT = "anixart-ios-probe/1.0"
TIMEOUT = 25

# Both the long-standing v3 API and the newer host, since the project has been
# moving between them.
ENDPOINTS = [
    ("v3", "https://api.anilibria.tv/v3/title/search?search={query}&limit=3"),
    ("top", "https://anilibria.top/api/v1/app/search/releases?query={query}&limit=3"),
]


def fetch(url: str, raw: bool = False):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            payload = response.read(2048) if raw else response.read()
            return response.status, response.headers.get("Content-Type", "?"), payload
    except urllib.error.HTTPError as error:
        return error.code, "?", b""
    except Exception as error:  # noqa: BLE001 - diagnostics
        print(f"  ! {url}: {error}", file=sys.stderr)
        return 0, "?", b""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("title", nargs="?", default="Киберпанк: Бегущие по краю")
    args = parser.parse_args()
    query = urllib.parse.quote(args.title)

    for name, template in ENDPOINTS:
        url = template.format(query=query)
        status, content_type, body = fetch(url)
        print(f"[{name}] {status} {content_type} {len(body)} bytes")
        if status != 200 or not body:
            continue

        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            print("  not JSON")
            continue

        # v3 wraps results in {"list": [...]}, the newer one returns a list.
        items = data.get("list") if isinstance(data, dict) else data
        if not items:
            print("  no matches")
            continue

        first = items[0]
        print("  match:", json.dumps(
            {k: first.get(k) for k in ("id", "code", "names", "name", "year") if k in first},
            ensure_ascii=False,
        )[:300])

        # v3 shape: player.list is a dict of episode -> {hls: {fhd,hd,sd}}
        player = first.get("player") or {}
        host = player.get("host")
        episodes = player.get("list") or {}
        if not episodes:
            print("  no player block; keys:", list(first.keys())[:15])
            continue

        number, episode = next(iter(episodes.items()))
        hls = (episode or {}).get("hls") or {}
        print(f"  host {host}, episode {number}, qualities {list(hls.keys())}")

        for quality, path in hls.items():
            if not path:
                continue
            stream = f"https://{host}{path}" if host else path
            status, content_type, head = fetch(stream, raw=True)
            playable = head.startswith(b"#EXTM3U")
            print(f"    {quality}: {status} {content_type} -> {'HLS playlist, playable' if playable else head[:40]!r}")
            print(f"      {stream}")
        return 0

    print("no endpoint answered usefully", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
