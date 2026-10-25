#!/usr/bin/env python3
"""Extract the filter's option lists from the decompiled APK's arrays.xml.

Genres, studios and countries are fixed lists the Android app ships rather than
fetching, so the port ships them too -- typing a genre by hand is not what the
original asks of you. The genre array uses `@`-prefixed entries as section
headers (`@Аудитория`, `@Тематика`), which is how the picker groups them.

Usage:
    jadx -d res-out --no-src Anixart.apk
    python3 extract-filter-options.py res-out/resources/res/values/arrays.xml > FilterOptions.swift
"""

import re
import sys


def arrays(text: str) -> dict[str, list[str]]:
    found = {}
    pattern = re.compile(r'<(string)?-?array name="([^"]+)">(.*?)</\1?-?array>', re.S)
    for match in pattern.finditer(text):
        found[match.group(2)] = re.findall(r"<item>(.*?)</item>", match.group(3), re.S)
    return found


def swift_literal(values: list[str], indent: str = "        ") -> str:
    return "\n".join(f'{indent}"{v}",' for v in values).rstrip(",")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2

    data = arrays(open(sys.argv[1], encoding="utf-8", errors="replace").read())

    # "Неважно" is the placeholder the spinner shows for "no constraint"; the port
    # renders that itself, so it is not an option.
    countries = [c for c in data["countries"] if c != "Неважно"]
    studios = [s for s in data["studios"] if s != "Неважно"]

    groups: list[tuple[str, list[str]]] = []
    current_title = "Жанры"
    current: list[str] = []
    for item in data["genres"]:
        if item.startswith("@"):
            groups.append((current_title, current))
            current_title, current = item[1:], []
        else:
            current.append(item)
    groups.append((current_title, current))

    out = [
        "// Generated from Anixart 10.5 res/values/arrays.xml by Tools/extract-filter-options.py.",
        "// These lists ship with the Android app rather than coming from the API.",
        "// Do not edit by hand.",
        "",
        "import Foundation",
        "",
        "/// Fixed option lists behind the catalogue filter.",
        "public enum FilterOptions {",
        "    /// `country` in the filter body. Sent as the label itself.",
        "    public static let countries: [String] = [",
        swift_literal(countries),
        "    ]",
        "",
        "    /// `studio`. 173 entries, sent as the label itself.",
        "    public static let studios: [String] = [",
        swift_literal(studios),
        "    ]",
        "",
        "    /// Genres, in the three groups the Android picker shows.",
        "    public struct GenreGroup: Hashable, Sendable, Identifiable {",
        "        public let title: String",
        "        public let genres: [String]",
        "        public var id: String { title }",
        "    }",
        "",
        "    public static let genreGroups: [GenreGroup] = [",
    ]
    for title, genres in groups:
        out.append(f'        GenreGroup(title: "{title}", genres: [')
        out.append(swift_literal(genres, "            "))
        out.append("        ]),")
    out[-1] = out[-1].rstrip(",")
    out += [
        "    ]",
        "",
        "    /// Every genre, flattened, in the order the app lists them.",
        "    public static let genres: [String] = genreGroups.flatMap(\\.genres)",
        "}",
        "",
    ]
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
