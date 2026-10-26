#!/usr/bin/env python3
"""How often does Anixart hand over a real stream rather than a player page?

The embedded and external players can only play a direct URL; an `iframe`
episode is the hosting's own page, whose stream sits behind that page's token
handling. Whether those two players are reachable at all therefore depends on
the mix the catalogue actually returns, and nothing in the port measured it.

This walks a page of the catalogue, and for each release takes every voice-over
and its first hosting, then counts the episodes by shape. It only reads public
endpoints, the same ones the app calls.

    python3 Tools/probe-stream-shapes.py [--releases N] [--api URL]
"""

import argparse
import json
import sys
import urllib.error
import urllib.request
from collections import Counter

DEFAULT_API = "https://api-s.anixsekai.com"
TIMEOUT = 30
# urllib's default agent gets a 403 from the API where curl's does not, so say
# plainly what this is instead.
USER_AGENT = "anixart-ios-probe/1.0"


def get(api: str, path: str, body: dict | None = None):
    url = f"{api}/{path}"
    data = json.dumps(body).encode() if body is not None else None
    headers = {"User-Agent": USER_AGENT}
    if data:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            return json.load(response)
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as error:
        print(f"  ! {path}: {error}", file=sys.stderr)
        return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--releases", type=int, default=10)
    parser.add_argument("--api", default=DEFAULT_API)
    args = parser.parse_args()

    page = get(args.api, "filter/0", {"sort": 1})
    releases = (page or {}).get("content") or []
    if not releases:
        # This is a measurement, not a correctness check: a bad day for the API
        # should not fail the build that the decode test is the real gate for.
        print("no releases returned; nothing to measure", file=sys.stderr)
        return 0

    shapes = Counter()
    per_hosting = Counter()
    releases_with_direct = 0
    releases_seen = 0

    for release in releases[: args.releases]:
        release_id = release.get("id")
        title = release.get("title_ru") or release.get("title_original") or release_id
        types = (get(args.api, f"episode/{release_id}") or {}).get("types") or []
        if not types:
            continue

        releases_seen += 1
        direct_here = 0

        for voice in types:
            sources = (get(args.api, f"episode/{release_id}/{voice['id']}") or {}).get("sources") or []
            if not sources:
                continue
            source = sources[0]
            episodes = (
                get(args.api, f"episode/{release_id}/{voice['id']}/{source['id']}?sort=0") or {}
            ).get("episodes") or []

            for episode in episodes:
                shape = "iframe" if episode.get("iframe") else "direct"
                shapes[shape] += 1
                per_hosting[(source.get("name") or "?", shape)] += 1
                if shape == "direct":
                    direct_here += 1

        if direct_here:
            releases_with_direct += 1
        print(f"  {title}: {direct_here} direct of {sum(shapes.values())} seen so far")

    total = sum(shapes.values())
    print()
    print(f"releases walked: {releases_seen}")
    print(f"episodes: {total}, iframe: {shapes['iframe']}, direct: {shapes['direct']}")
    if total:
        print(f"direct share: {shapes['direct'] / total:.1%}")
    print(f"releases with at least one direct episode: {releases_with_direct}/{releases_seen}")

    print("\nby hosting:")
    hostings = sorted({name for name, _ in per_hosting})
    for name in hostings:
        direct = per_hosting[(name, "direct")]
        iframe = per_hosting[(name, "iframe")]
        print(f"  {name}: direct {direct}, iframe {iframe}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
