#!/usr/bin/env python3
"""Extract Anixart's wire format from a decompiled APK.

The Android app serialises with Jackson, and its entities carry explicit
`@JsonProperty` annotations. Reading those gives the server's real JSON keys,
which matters because the API mixes snake_case and camelCase in the same object
-- so no blanket key strategy works and the mapping cannot be guessed.

Usage:
    jadx -d out --no-res Anixart.apk
    python3 extract-models.py out/sources/com/swiftsoft/anixartd > model-map.json

Emits, per class: the source file, the superclass (and its generic argument, for
`Comment<ProfileCompact>`), and for every property its Java name, its JSON key,
its Java type, and whether it has a backing field (computed-only getters are not
part of the wire format).
"""

import json
import os
import re
import sys

ROOTS = ["database/entity", "network/response", "network/request"]

GETTER_RE = re.compile(
    r'public\s+(?:final\s+)?([A-Za-z0-9_.<>,\[\]\? ]+?)\s+(get[A-Z]\w*|is[A-Z]\w*)\s*\(\s*\)'
)
JSON_PROPERTY_RE = re.compile(r'@JsonProperty\("([^"]+)"\)')
FIELD_RE = re.compile(
    r'^\s*(?:private|public|protected)\s+(?:static\s+|final\s+|transient\s+)*'
    r'([A-Za-z0-9_.<>,\[\]\? ]+?)\s+(\w+)\s*(?:=|;)',
    re.M,
)
CLASS_RE = re.compile(
    r'public\s+(?:abstract\s+|final\s+|static\s+)*class\s+(\w+)(?:<[^>]*>)?\s*'
    r'(?:extends\s+([\w.]+)(?:<([^>]*)>)?)?'
)


def property_name(getter: str) -> str:
    """`getTitleRu` -> `titleRu`, while `isFiller` stays as it is."""
    return getter[3].lower() + getter[4:] if getter.startswith("get") else getter


def parse(path: str) -> dict | None:
    # jadx writes Kotlin's @Metadata blob as one enormous line; drop it first.
    text = "\n".join(
        line for line in open(path, encoding="utf-8", errors="replace").read().split("\n")
        if "@Metadata" not in line
    )

    field_types: dict[str, str] = {}
    for match in FIELD_RE.finditer(text):
        field_types.setdefault(match.group(2), match.group(1).strip())

    class_match = CLASS_RE.search(text)
    parent = class_match.group(2).split(".")[-1] if class_match and class_match.group(2) else None
    parent_arg = None
    if class_match and class_match.group(3):
        parent_arg = class_match.group(3).split("<")[0].strip()

    lines = text.split("\n")
    props, seen = [], set()
    for index, line in enumerate(lines):
        getter = GETTER_RE.search(line)
        if not getter:
            continue

        # The annotation sits on one of the lines just above the getter.
        json_key = None
        for back in range(1, 4):
            if index - back < 0:
                break
            annotation = JSON_PROPERTY_RE.search(lines[index - back])
            if annotation:
                json_key = annotation.group(1)
                break
            if "public" in lines[index - back] or "}" in lines[index - back]:
                break

        name = property_name(getter.group(2))
        if name in seen:
            continue
        seen.add(name)
        props.append({
            "prop": name,
            "json": json_key or name,
            "type": field_types.get(name) or getter.group(1).strip(),
            "hasField": name in field_types,
        })

    if not props:
        return None
    return {"parent": parent, "parentArg": parent_arg, "props": props}


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2

    source_root = sys.argv[1]
    out = {}
    for root in ROOTS:
        for dirpath, _, filenames in os.walk(os.path.join(source_root, root)):
            for filename in filenames:
                if not filename.endswith(".java"):
                    continue
                path = os.path.join(dirpath, filename)
                parsed = parse(path)
                if parsed:
                    parsed["file"] = os.path.relpath(path, source_root)
                    out[filename[:-5]] = parsed

    print(json.dumps(out, indent=1, ensure_ascii=False))
    print(f"extracted {len(out)} classes", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
