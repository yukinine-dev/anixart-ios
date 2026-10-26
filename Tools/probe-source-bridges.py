#!/usr/bin/env python3
"""Which other hostings put a usable id in the URL Anixart already gives us?

The Libria bridge works because `anixart.libria.fun/...?id=9307&ep=1` carries
AniLibria's own release id, so its public API can be asked for the stream. The
question this answers is which other hostings do the same, since each one is
another source the built-in player could use.

It walks several releases, groups every episode URL by host, and prints one
example per host with its query keys -- enough to see whether an id is there.
For RuTube, which publishes a play-options API, it goes further and asks for the
stream.

    python3 Tools/probe-source-bridges.py --releases 12
"""

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

ANIXART_API = "https://api-s.anixsekai.com"
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


def libria(release_id: str) -> None:
    """The id in a libria.fun URL should be AniLibria's own release id."""
    status, content_type, body = get(f"https://anilibria.top/api/v1/anime/releases/{release_id}")
    print(f"      anilibria releases/{release_id}: {status} {content_type}")
    if status != 200 or not body:
        return
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        print("      not JSON")
        return
    name = data.get("name") or {}
    episodes = data.get("episodes") or []
    rungs = sorted(k for k in (episodes[0] if episodes else {}) if k.startswith("hls_")
                   and (episodes[0] if episodes else {}).get(k))
    print(f"      {name.get('main')!r} ({data.get('year')}), {len(episodes)} episodes, first offers {rungs}")


def rutube(video_id: str) -> None:
    """RuTube publishes play options, which name the HLS playlist directly."""
    status, content_type, body = get(f"https://rutube.ru/api/play/options/{video_id}/?no_404=true")
    print(f"      play/options: {status} {content_type}")
    if status != 200 or not body:
        return
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        print("      not JSON")
        return

    playlist = ((data.get("video_balancer") or {}).get("m3u8")
                or (data.get("video_balancer") or {}).get("default"))
    if not playlist:
        print(f"      no m3u8 in keys {sorted(data.keys())[:12]}")
        return
    status, content_type, head = get(playlist, raw=True)
    verdict = "HLS playlist, playable" if head.startswith(b"#EXTM3U") else repr(head[:40])
    print(f"      m3u8: {status} {content_type} -> {verdict}")
    print(f"        {playlist}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--releases", type=int, default=12)
    args = parser.parse_args()

    # host -> (hosting name, example url, how many episodes seen)
    seen: dict[str, list] = {}
    # Kodik is on nearly every voice-over, so fetching its episode list again
    # for each one would be most of the run for no new information.
    known_hostings: set[str] = set()

    for _ in range(args.releases):
        random = anixart("release/random?extended_mode=true")
        release = (random or {}).get("release") or {}
        release_id = release.get("id")
        if not release_id:
            continue

        for voice in (anixart(f"episode/{release_id}") or {}).get("types") or []:
            for source in (anixart(f"episode/{release_id}/{voice['id']}") or {}).get("sources") or []:
                name = source.get("name") or "?"
                if name in known_hostings:
                    continue
                known_hostings.add(name)
                episodes = (
                    anixart(f"episode/{release_id}/{voice['id']}/{source['id']}?sort=0") or {}
                ).get("episodes") or []
                for episode in episodes:
                    url = episode.get("url")
                    if not url:
                        continue
                    host = urllib.parse.urlparse(url).netloc
                    if host not in seen:
                        seen[host] = [name, url, 0]
                    seen[host][2] += 1

    print(f"\n{len(seen)} hosts across {args.releases} releases\n")
    for host, (hosting, url, count) in sorted(seen.items(), key=lambda item: -item[1][2]):
        parsed = urllib.parse.urlparse(url)
        query = sorted(urllib.parse.parse_qs(parsed.query).keys())
        print(f"{host}  ({hosting}, {count} episodes)")
        print(f"    path  {parsed.path}")
        print(f"    query {query}")
        print(f"    e.g.  {url}")

        if "libria" in host:
            # Both the hosting Anixart calls Libria and the one it calls Liberty
            # sit on this host, so one bridge covers both -- if the id means the
            # same thing for each.
            ident = urllib.parse.parse_qs(parsed.query).get("id", [""])[0]
            print(f"    libria id {ident}")
            if ident:
                libria(ident)

        if "rutube" in host:
            # The id is the last path component for rutube.ru/play/embed/<id>.
            video_id = parsed.path.rstrip("/").split("/")[-1]
            print(f"    rutube id {video_id}")
            rutube(video_id)
        print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
