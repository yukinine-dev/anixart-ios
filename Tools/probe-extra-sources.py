#!/usr/bin/env python3
"""Which other services publish streams we could actually play?

AniLibria covers the Libria and Liberty hostings, but most of Anixart's
voice-overs sit on Kodik, whose player page guards its stream. So the question
is not "how do we open Kodik" but "which services publish their own dubs through
an API", because those are dubs the built-in player could offer alongside.

Anixart carries no external ids -- no Shikimori, MAL, WorldArt or Kinopoisk --
so the bridge has to be Shikimori's own search, and every hop is reported here
with its candidates so the match quality can be judged rather than assumed.

    python3 Tools/probe-extra-sources.py "Киберпанк: Бегущие по краю"
"""

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

USER_AGENT = "anixart-ios-probe/1.0"
TIMEOUT = 25

ANIXART_API = "https://api-s.anixsekai.com"
SHIKIMORI_API = "https://shikimori.one/api"
# Shikimori's API asks callers to name themselves in the User-Agent.
SHIKIMORI_HEADERS = {"Accept": "application/json", "User-Agent": "anixart-ios-port"}
# The host the AnimeLib clients talk to; Site-Id 5 is its anime catalogue.
ANIMELIB_HOSTS = [
    "https://api.cdnlibs.org/api",
    "https://api.lib.social/api",
]
ANIMELIB_HEADERS = {"Accept": "application/json", "Site-Id": "5"}


def get(url: str, headers: dict | None = None, raw: bool = False):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **(headers or {})})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            payload = response.read(2048) if raw else response.read()
            return response.status, response.headers.get("Content-Type", "?"), payload
    except urllib.error.HTTPError as error:
        return error.code, error.headers.get("Content-Type", "?") if error.headers else "?", b""
    except Exception as error:  # noqa: BLE001 - diagnostics
        print(f"  ! {url}: {error}", file=sys.stderr)
        return 0, "?", b""


def get_json(url: str, headers: dict | None = None):
    status, content_type, body = get(url, headers)
    if status != 200 or not body:
        print(f"    HTTP {status} {content_type}")
        return None
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        print(f"    not JSON ({len(body)} bytes)")
        return None


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


def anixart_hostings(title: str):
    """What Anixart offers for the title, and how much of it is Kodik."""
    found = anixart("search/releases/0", {"query": title, "searchBy": 0})
    releases = (found or {}).get("content") or []
    if not releases:
        print(f"  nothing on Anixart for {title!r}")
        return None

    release = releases[0]
    print(f"  anixart: {release.get('title_ru')!r} / {release.get('title_original')!r}"
          f" ({release.get('year')}), {release.get('episodes_total')} episodes, id {release['id']}")

    counts: dict[str, int] = {}
    types = (anixart(f"episode/{release['id']}") or {}).get("types") or []
    for voice in types:
        for source in (anixart(f"episode/{release['id']}/{voice['id']}") or {}).get("sources") or []:
            name = source.get("name") or "?"
            counts[name] = counts.get(name, 0) + 1
    print(f"  {len(types)} voice-overs; hostings: {counts}")
    return release


def shikimori(release) -> int | None:
    """Anixart has no external ids, so this is the only way across."""
    for key in ("title_original", "title_ru"):
        query = release.get(key)
        if not query:
            continue
        url = f"{SHIKIMORI_API}/animes?search={urllib.parse.quote(query)}&limit=5"
        print(f"  shikimori search by {key}: {query!r}")
        items = get_json(url, SHIKIMORI_HEADERS)
        if not items:
            continue
        for item in items:
            print(f"    id {item.get('id')}  {item.get('name')!r} / {item.get('russian')!r}"
                  f"  aired {item.get('aired_on')}  episodes {item.get('episodes')}")
        # Only accept a year match, since a franchise search returns siblings.
        year = str(release.get("year") or "")
        for item in items:
            if year and str(item.get("aired_on") or "").startswith(year[:4]):
                print(f"    -> taking {item.get('id')} on a year match ({year})")
                return item.get("id")
        print("    -> no candidate matches the year")
    return None


def animelib(release, shikimori_id: int | None):
    """AnimeLib publishes its own dubs, several teams per title."""
    query = release.get("title_original") or release.get("title_ru")
    print(f"  animelib search: {query!r}")

    found = None
    api = None
    for host in ANIMELIB_HOSTS:
        print(f"    via {host}")
        found = get_json(f"{host}/anime?q={urllib.parse.quote(query)}", ANIMELIB_HEADERS)
        if found:
            api = host
            break
    if not found:
        print("    no AnimeLib host answered this client")
        return
    items = found.get("data") if isinstance(found, dict) else found
    if not items:
        print("    no matches")
        return

    for item in items[:5]:
        print(f"    {item.get('slug_url')!r}  {item.get('rus_name')!r}"
              f"  shikimori {item.get('shikimori_href')}")

    chosen = items[0]
    if shikimori_id:
        for item in items:
            if str(shikimori_id) in str(item.get("shikimori_href") or ""):
                chosen = item
                print(f"    -> {item.get('slug_url')} confirmed by shikimori id {shikimori_id}")
                break
        else:
            print(f"    -> no candidate names shikimori id {shikimori_id}; taking the first")

    slug = chosen.get("slug_url")
    episodes = get_json(f"{api}/episodes?anime_id={urllib.parse.quote(str(slug))}", ANIMELIB_HEADERS)
    rows = (episodes or {}).get("data") if isinstance(episodes, dict) else episodes
    if not rows:
        print("    no episode list")
        return
    print(f"    {len(rows)} episodes; first keys: {sorted(rows[0].keys())}")

    detail = get_json(f"{api}/episodes/{rows[0].get('id')}", ANIMELIB_HEADERS)
    data = (detail or {}).get("data") if isinstance(detail, dict) else detail
    if not data:
        print("    no episode detail")
        return
    print(f"    episode keys: {sorted(data.keys())}")

    players = data.get("players") or []
    print(f"    {len(players)} players")
    for player in players[:6]:
        team = (player.get("team") or {}).get("name")
        qualities = [q.get("quality") for q in ((player.get("video") or {}).get("quality") or [])]
        print(f"      {player.get('player')!r} team {team!r} qualities {qualities}")

    # Verify one is really media, the way AVFoundation would ask.
    for player in players:
        for quality in ((player.get("video") or {}).get("quality") or []):
            href = quality.get("href")
            if not href:
                continue
            stream = href if href.startswith("http") else f"https://video1.anilib.me{href}"
            status, content_type, head = get(stream, {"Referer": "https://anilib.me/"}, raw=True)
            looks = ("MP4" if head[4:8] == b"ftyp"
                     else "HLS" if head.startswith(b"#EXTM3U")
                     else repr(head[:32]))
            print(f"    stream: {status} {content_type} -> {looks}")
            print(f"      {stream}")
            return


def kodik():
    """Kodik's API needs a token its own player hands out; recorded, not used."""
    status, content_type, _ = get("https://kodikapi.com/search?title=test")
    print(f"  kodikapi.com/search without a token: HTTP {status} {content_type}")
    print("  (its search returns a player link in any case, not a stream)")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("title", nargs="?", default="Киберпанк: Бегущие по краю")
    args = parser.parse_args()

    print("== anixart ==")
    release = anixart_hostings(args.title)
    if release is None:
        return 0

    print("\n== shikimori (the bridge) ==")
    shikimori_id = shikimori(release)

    print("\n== animelib ==")
    animelib(release, shikimori_id)

    print("\n== kodik ==")
    kodik()
    return 0


if __name__ == "__main__":
    sys.exit(main())
