#!/usr/bin/env python3
"""Can the built-in player be fed from Kodik at all?

The server's own config names the endpoint: `kodikVideoLinksUrl` is
`https://kodikplayer.com/get-video-info`, and `KodikParser` in the APK posts to
it. What it posts is behind LSParanoid, so this does not try to read it -- it
reads the player page, which has to carry the same parameters, and reports what
comes back.

Nothing here asserts. It prints what the page offers, what was sent (names and
lengths only -- the values are signed tokens and this log is public), and the
shape of the answer. That is the measurement the built-in Kodik path needs
before a line of Swift is written for it; the last two rounds of this work were
lost to building against a shape I had assumed.

    python3 Tools/probe-kodik-video-info.py "Киберпанк: Бегущие по краю"
"""

import argparse
import builtins
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request


def print(*args, **kwargs):  # noqa: A001 - deliberate shadow, this is a script
    builtins.print("info|", *args, **kwargs)


ANIXART_API = "https://api-s.anixsekai.com"
USER_AGENT = "anixart-ios-probe/1.0"
REFERER = "https://anixart-app.com"
VERSION = "26101718"
TIMEOUT = 25


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
        print(f"! {path}: {error}")
        return None


def video_links_url() -> str:
    query = f"version_code={VERSION}&is_beta=false&is_api_alt=false"
    toggles = anixart(f"config/toggles?{query}") or {}
    url = toggles.get("kodikVideoLinksUrl")
    if url:
        print(f"  config kodikVideoLinksUrl = {url}")
        return url
    print("  config did not name kodikVideoLinksUrl; using the known default")
    return "https://kodikplayer.com/get-video-info"


def kodik_episode(title: str) -> str | None:
    """The first Kodik episode of the first voice-over of a release."""
    # Search is a POST with a body; the path form answers 404.
    found = anixart("search/releases/0", {"query": title, "searchBy": 0}) or {}
    releases = found.get("content") or []
    if not releases:
        print(f"  nothing found for {title!r}")
        return None
    release = releases[0]
    print(f"  anixart: {release.get('title_ru')!r} id {release.get('id')}")

    types = (anixart(f"episode/{release['id']}") or {}).get("types") or []
    for kind in types:
        sources = (anixart(f"episode/{release['id']}/{kind['id']}") or {}).get("sources") or []
        for source in sources:
            episodes = (
                anixart(f"episode/{release['id']}/{kind['id']}/{source['id']}?sort=0") or {}
            ).get("episodes") or []
            for episode in episodes:
                url = (episode.get("url") or "").split('"')[0].strip()
                if "kodik" in url or "aniqit" in url:
                    print(f"  via {kind.get('name')} / {source.get('name')}")
                    return url
    return None


def page(url: str) -> str | None:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Referer": REFERER})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            print(f"  page: HTTP {response.status}")
            return response.read(400_000).decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        print(f"  page: HTTP {error.code}")
    except Exception as error:  # noqa: BLE001
        print(f"  page unreachable: {error}")
    return None


def parameters(body: str, url: str) -> dict:
    """Everything the page hands the player, plus what the path carries."""
    params: dict[str, str] = {}

    # The page assigns a urlParams blob; it is a JSON object however it is quoted.
    for blob in re.findall(r"urlParams\s*=\s*['\"](\{.*?\})['\"]", body, re.S):
        try:
            params.update({k: str(v) for k, v in json.loads(blob.replace("\\'", "'")).items()})
        except Exception:  # noqa: BLE001
            continue

    # Bare assignments the player script reads: var hash = "..."; var id = 123;
    for name in ("hash", "id", "type", "videoType", "translationId"):
        match = re.search(rf"\b{name}\s*=\s*['\"]?([A-Za-z0-9_-]+)['\"]?\s*;", body)
        if match and name not in params:
            params[name] = match.group(1)

    # /seria/1050232/<hash>/720p -- the path carries the same three.
    parts = [p for p in urllib.parse.urlsplit(url).path.split("/") if p]
    if len(parts) >= 3:
        params.setdefault("type", parts[0])
        params.setdefault("id", parts[1])
        params.setdefault("hash", parts[2])

    return params


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("title", nargs="?", default="Киберпанк: Бегущие по краю")
    args = parser.parse_args()

    endpoint = video_links_url()
    url = kodik_episode(args.title)
    if not url:
        print("  no Kodik episode to try")
        return 0
    print(f"  episode {url}")

    body = page(url)
    if body is None:
        return 0

    params = parameters(body, url)
    if not params:
        print("  the page carries none of the parameters the endpoint needs")
        return 0
    # Names and lengths only: these are signed tokens and this log is public.
    print("  parameters the page carries:")
    for key in sorted(params):
        value = params[key]
        shown = value if (value.isdigit() or len(value) <= 12) else f"<{len(value)} chars>"
        print(f"    {key} = {shown}")

    data = urllib.parse.urlencode(params).encode()
    request = urllib.request.Request(
        endpoint,
        data=data,
        headers={
            "User-Agent": USER_AGENT,
            "Referer": url,
            "Origin": "https://kodikplayer.com",
            "Content-Type": "application/x-www-form-urlencoded",
            "X-Requested-With": "XMLHttpRequest",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            status = response.status
            answer = response.read(200_000).decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        answer = error.read(20_000).decode("utf-8", "replace") if error.fp else ""
        print(f"  get-video-info: HTTP {error.code} {answer[:200]!r}")
        return 0
    except Exception as error:  # noqa: BLE001
        print(f"  get-video-info unreachable: {error}")
        return 0

    print(f"  get-video-info: HTTP {status} {len(answer)} chars")
    try:
        parsed = json.loads(answer)
    except Exception:  # noqa: BLE001
        print(f"  not JSON: {answer[:300]!r}")
        return 0

    print(f"  keys: {sorted(parsed)}")
    links = parsed.get("links")
    if not isinstance(links, dict):
        print(f"  no 'links' object; body starts {answer[:300]!r}")
        return 0

    print(f"  qualities: {sorted(links, key=lambda q: -int(re.sub(r'[^0-9]', '', q) or 0))}")
    for quality, entries in sorted(links.items()):
        if not isinstance(entries, list) or not entries:
            continue
        first = entries[0]
        src = first.get("src") if isinstance(first, dict) else first
        src = str(src)
        looks = "a URL" if src.startswith("http") or src.startswith("//") else "encoded"
        print(f"    {quality}: {looks}, {len(src)} chars, starts {src[:28]!r}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
