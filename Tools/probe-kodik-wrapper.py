#!/usr/bin/env python3
"""Where is the page that wraps Kodik's player?

`KodikAdActivity` does not open the episode's URL. It takes the URL, strips the
query, percent-encodes it, appends it to a base URL read from `Prefs`, adds
`&v=26101718` (the Android versionCode) and loads *that*. The wrapper is what
shows the advert and what calls `KodikInterface.advertEnded()` -- which is why
opening Kodik's URL directly answers "данной страницы не существует".

The base URL is behind LSParanoid and my decoder for it does not work, so this
tries the plausible ones instead. The test is objective rather than hopeful: a
wrapper has to mention `KodikInterface` or `advertEnded`, because that is the
bridge it talks to. Anything else is not it, and if none matches, none matches.

    python3 Tools/probe-kodik-wrapper.py
"""

import argparse
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

# `anixart-app.com` is the only app domain in the APK's resources, so the paths
# are guesses; the match criterion is not.
CANDIDATES = [
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

    for base in CANDIDATES:
        url = f"{base}{encoded}&v={VERSION}"
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
                status = response.status
                body = response.read(300_000).decode("utf-8", "replace")
        except urllib.error.HTTPError as error:
            print(f"wrapper| {base} -> HTTP {error.code}")
            continue
        except Exception as error:  # noqa: BLE001 - diagnostics
            print(f"wrapper| {base} -> {error}")
            continue

        found = [marker for marker in MARKERS if marker in body]
        verdict = f"mentions {found}" if found else "no marker"
        print(f"wrapper| {base} -> HTTP {status} {len(body)} chars, {verdict}")
        if found:
            print(f"wrapper|   FOUND {url}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
