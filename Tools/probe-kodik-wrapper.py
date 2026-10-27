#!/usr/bin/env python3
"""Where is the page that wraps Kodik's player?

`KodikAdActivity` does not open the episode's URL. It takes the URL, strips the
query, percent-encodes it, appends it to a base URL read from `Prefs`, adds
`&v=26101718` (the Android versionCode) and loads *that*. The wrapper is what
shows the advert and what calls `KodikInterface.advertEnded()` -- which is why
opening Kodik's URL directly answers "данной страницы не существует".

The base URL is behind LSParanoid, but it does not have to be decoded: the
server sends it. `config/toggles` carries `kodikAdIframeUrl` and
`iframeEmbedUrl`, and the app reads the base from there, so this asks the live
config first and only falls back to guessing. Guessing is what wasted the last
round -- every `anixart-app.com` path answered with the same 183083-char
single-page app, because none of them was the wrapper.

    python3 Tools/probe-kodik-wrapper.py
"""

import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
)
VERSION = "26101718"
TIMEOUT = 20

ANIXART_API = "https://api-s.anixsekai.com"

# Only reached if the live config cannot be read. `anixart-app.com` is the one
# app domain in the APK's resources, so these paths are guesses; the match
# criterion below is not.
FALLBACK = [
    "https://anixart-app.com/?url=",
    "https://anixart-app.com/ad?url=",
    "https://anixart-app.com/ad/?url=",
    "https://anixart-app.com/ads?url=",
    "https://anixart-app.com/kodik?url=",
    "https://anixart-app.com/kodik/?url=",
    "https://anixart-app.com/player?url=",
    "https://anixart-app.com/player/?url=",
    "https://anixart-app.com/embed?url=",
    "https://anixart-app.com/e?url=",
    "https://anixart-app.com/v?url=",
    "https://anixart-app.com/watch?url=",
]

MARKERS = ["KodikInterface", "advertEnded", "adsbygoogle"]


def live_bases() -> list[tuple[str, str]]:
    """The wrapper bases the server itself hands the app."""
    request = urllib.request.Request(
        f"{ANIXART_API}/config/toggles", headers={"User-Agent": USER_AGENT}
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            toggles = json.loads(response.read())
    except Exception as error:  # noqa: BLE001 - diagnostics
        print(f"wrapper| config/toggles unreadable: {error}")
        return []

    bases = []
    for key in ("kodikAdIframeUrl", "iframeEmbedUrl"):
        value = toggles.get(key)
        if isinstance(value, str) and value:
            print(f"wrapper| config {key} = {value}")
            bases.append((key, value))
    return bases


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "episode",
        nargs="?",
        default="https://kodikplayer.com/seria/1050232/7928476d465322676fca502907770509/720p",
    )
    args = parser.parse_args()

    bare = urllib.parse.urlsplit(args.episode)
    stripped = urllib.parse.urlunsplit((bare.scheme, bare.netloc, bare.path, "", ""))
    encoded = urllib.parse.quote(stripped, safe="")
    print(f"wrapper| episode {stripped}")

    bases = live_bases()
    if not bases:
        bases = [("guess", base) for base in FALLBACK]

    for label, base in bases:
        url = f"{base}{encoded}&v={VERSION}"
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
                status = response.status
                body = response.read(300_000).decode("utf-8", "replace")
        except urllib.error.HTTPError as error:
            print(f"wrapper| {label} {base} -> HTTP {error.code}")
            continue
        except Exception as error:  # noqa: BLE001 - diagnostics
            print(f"wrapper| {label} {base} -> {error}")
            continue

        found = [marker for marker in MARKERS if marker in body]
        verdict = f"mentions {found}" if found else "no marker"
        print(f"wrapper| {label} {base} -> HTTP {status} {len(body)} chars, {verdict}")
        # Whether the wrapper actually embeds the episode is the other half of
        # the question: a page that shows an advert and never loads the player
        # is no more use than the 404 was.
        if stripped in body or urllib.parse.quote(stripped, safe="") in body:
            print("wrapper|   the page carries the episode URL")
        for frame in re.findall(r"<iframe[^>]+src=[\"\']([^\"\']+)", body)[:5]:
            print(f"wrapper|   iframe {frame}")
        if found:
            print(f"wrapper|   FOUND {url}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
