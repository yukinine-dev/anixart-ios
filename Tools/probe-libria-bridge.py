#!/usr/bin/env python3
"""Can AniLibria's own API fill in the stream Anixart withholds?

Anixart hands out no playable URLs: every hosting serves its own player page.
But its "Libria" hosting points at `anixart.libria.fun/public/iframe.php?id=N&ep=M`,
and `N` looks like AniLibria's own release id -- the search probe found release
9307 for "Киберпанк: Бегущие по краю", the same number Anixart puts in that URL.

If that holds, the built-in player needs no title matching and no scraping of
anyone's player: read the id out of the URL Anixart already gives us, then ask
AniLibria's public API for the HLS playlist of that release and episode.

This checks the whole chain on a real title: the id in Anixart's URL, the
release AniLibria returns for it, the episode list, and the first bytes of the
playlist the way a player would fetch them.

    python3 Tools/probe-libria-bridge.py "Киберпанк: Бегущие по краю"
"""

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

ANIXART_API = "https://api-s.anixsekai.com"
LIBRIA_API = "https://anilibria.top/api/v1"
USER_AGENT = "anixart-ios-probe/1.0"
TIMEOUT = 25


def get(url: str, raw: bool = False, headers: dict | None = None):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **(headers or {})})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            payload = response.read(2048) if raw else response.read()
            return response.status, response.headers.get("Content-Type", "?"), payload
    except urllib.error.HTTPError as error:
        return error.code, "?", b""
    except Exception as error:  # noqa: BLE001 - diagnostics
        print(f"  ! {url}: {error}", file=sys.stderr)
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
        print(f"  ! {path}: {error}", file=sys.stderr)
        return None


def libria(path: str):
    status, content_type, body = get(f"{LIBRIA_API}/{path}")
    if status != 200 or not body:
        print(f"  [{path}] HTTP {status} {content_type}")
        return None
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        print(f"  [{path}] not JSON")
        return None


def libria_ids(release_id: int) -> dict[int, list[int]]:
    """Every (AniLibria release id -> episode numbers) Anixart's Libria source names."""
    found: dict[int, list[int]] = {}
    for voice in (anixart(f"episode/{release_id}") or {}).get("types") or []:
        sources = (anixart(f"episode/{release_id}/{voice['id']}") or {}).get("sources") or []
        for source in sources:
            episodes = (
                anixart(f"episode/{release_id}/{voice['id']}/{source['id']}?sort=0") or {}
            ).get("episodes") or []
            for episode in episodes:
                url = episode.get("url") or ""
                if "libria" not in url:
                    continue
                query = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
                try:
                    ident = int(query.get("id", ["0"])[0])
                    number = int(query.get("ep", ["0"])[0])
                except ValueError:
                    continue
                if ident:
                    found.setdefault(ident, []).append(number)
            if found:
                print(f"  via {voice.get('name')} / {source.get('name')}")
                return found
    return found


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("title", nargs="?", default="Киберпанк: Бегущие по краю")
    args = parser.parse_args()

    found = anixart("search/releases/0", {"query": args.title, "searchBy": 0})
    releases = (found or {}).get("content") or []
    if not releases:
        print(f"nothing found for {args.title!r}", file=sys.stderr)
        return 0
    release = releases[0]
    print(f"anixart: {release.get('title_ru')!r} ({release.get('year')}) id {release['id']}")

    ids = libria_ids(release["id"])
    if not ids:
        print("  Anixart lists no Libria source for this title")
        return 0
    print(f"  libria ids in Anixart's URLs: { {k: v[:5] for k, v in ids.items()} }")

    ident = next(iter(ids))
    episode_numbers = sorted(ids[ident])

    # Does that id mean the same release on AniLibria's side?
    detail = libria(f"anime/releases/{ident}")
    if detail is None:
        return 0
    name = detail.get("name") or {}
    print(f"  anilibria {ident}: {name.get('main')!r} / {name.get('english')!r} ({detail.get('year')})")
    print(f"    keys: {sorted(detail.keys())}")

    episodes = detail.get("episodes")
    if not episodes:
        # Some deployments keep the episode list behind its own path.
        episodes = libria(f"anime/releases/{ident}/episodes") or []
    if not isinstance(episodes, list) or not episodes:
        print("    no episode list on either path")
        return 0

    print(f"    {len(episodes)} episodes; Anixart named {episode_numbers[:5]}")
    first = episodes[0]
    print(f"    episode keys: {sorted(first.keys())}")
    print("    episode:", json.dumps(
        {k: v for k, v in first.items() if not isinstance(v, (dict, list))},
        ensure_ascii=False,
    )[:600])

    for key, value in sorted(first.items()):
        if not isinstance(value, str) or "hls" not in key:
            continue
        stream = value if value.startswith("http") else f"https://anilibria.top{value}"
        status, content_type, head = get(stream, raw=True, headers={"Referer": "https://anilibria.top/"})
        playable = head.startswith(b"#EXTM3U")
        print(f"    {key}: {status} {content_type} -> {'HLS playlist, playable' if playable else head[:48]!r}")
        print(f"      {stream}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
