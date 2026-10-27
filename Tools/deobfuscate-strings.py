#!/usr/bin/env python3
"""Recovers the APK's string literals, which LSParanoid encodes.

Every string constant in the Anixart APK is stored as a call like
`llI11lllIIll11l1Il1IlI1l1lIII1lI.IIlll1lIIl(-5104528844342L)`, so a decompiled
class shows its control flow but none of its text. That is the whole app, not
anything Kodik or any other hosting put there: the API paths this port already
uses were obfuscated the same way.

LSParanoid (org.lsposed.lsparanoid, open source) keeps one char table and
derives a keystream from the id, so decoding is arithmetic:

    python3 Tools/deobfuscate-strings.py <decompiled-root> <file.java>

prints every id in that file next to its string, in source order.
"""

import argparse
import pathlib
import re
import sys

MASK = (1 << 64) - 1
CHUNK = 8191


def s64(value: int) -> int:
    """Java long: two's complement, 64 bits."""
    value &= MASK
    return value - (1 << 64) if value >> 63 else value


def ushr(value: int, bits: int) -> int:
    """Java's `>>>` on a long."""
    return (value & MASK) >> bits


def to_short(value: int) -> int:
    value &= 0xFFFF
    return value - 0x10000 if value & 0x8000 else value


def rotl16(value: int, bits: int) -> int:
    value &= 0xFFFF
    return to_short((value << bits) | (value >> (16 - bits)))


def next_state(state: int) -> int:
    """RandomHelper.next: two 16-bit words through a xoroshiro-style step.

    jadx renders this as one expression with the terms out of order; this is the
    upstream form, which is what the ids were generated with.
    """
    s0 = to_short(state)
    s1 = to_short(ushr(state, 16))

    result = to_short(rotl16(to_short(s0 + s1), 9) + s0)
    s1 ^= s0
    new_s0 = to_short(rotl16(s0, 13) ^ s1 ^ (s1 << 5))
    new_s1 = rotl16(s1, 10)

    return ((result & 0xFFFF) << 32) | ((new_s1 & 0xFFFF) << 16) | (new_s0 & 0xFFFF)


def seed(value: int) -> int:
    """The splitmix-style scramble the generated decoder applies to the id."""
    low = value & 0xFFFFFFFF
    mixed = ((low ^ (low >> 33)) * 7109453100751455733) & MASK
    mixed = ((mixed ^ ushr(mixed, 28)) * (-3808689974395783757 & MASK)) & MASK
    return ushr(mixed, 32)


def load_chunks(decoder: pathlib.Path) -> list[str]:
    text = decoder.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"String\[\]\s+\w+\s*=\s*\{(.*?)\};", text, re.S)
    if not match:
        raise SystemExit(f"no char table in {decoder}")
    literals = re.findall(r'"((?:[^"\\]|\\.)*)"', match.group(1), re.S)
    return [lit.encode().decode("unicode_escape") for lit in literals]


def decode(ident: int, chunks: list[str]) -> str:
    state = next_state(seed(ident))
    low = ushr(state, 32) & 0xFFFF
    state = next_state(state)

    index = (ushr(ident, 32) ^ low) ^ (ushr(state, 16) & 0xFFFFFFFFFFFF0000)
    index &= 0xFFFFFFFF
    if index & 0x80000000:
        index -= 1 << 32

    def char_at(position: int) -> int:
        return ord(chunks[position // CHUNK][position % CHUNK])

    state = next_state(state) ^ (char_at(index) << 32)
    length = ushr(state, 32) & 0xFFFF

    out = []
    for step in range(length):
        position = index + step + 1
        state = next_state(state) ^ (char_at(position) << 32)
        out.append(chr(ushr(state, 32) & 0xFFFF))
    return "".join(out)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=pathlib.Path, help="decompiled sources root")
    parser.add_argument("target", type=pathlib.Path, help="a .java file to read")
    args = parser.parse_args()

    decoders = list(args.root.rglob("llI11lllIIll11l1Il1IlI1l1lIII1lI.java"))
    if not decoders:
        raise SystemExit("no LSParanoid decoder under that root")
    chunks = load_chunks(decoders[0])
    print(f"table: {len(chunks)} chunks, {sum(len(c) for c in chunks)} chars", file=sys.stderr)

    text = args.target.read_text(encoding="utf-8", errors="replace")
    ids = re.findall(r"IIlll1lIIl\((-?\d+)L\)", text)
    seen: set[int] = set()
    for raw in ids:
        ident = s64(int(raw)) & MASK
        if ident in seen:
            continue
        seen.add(ident)
        try:
            print(f"{int(raw):>16} = {decode(ident, chunks)!r}")
        except Exception as error:  # noqa: BLE001 - report and carry on
            print(f"{int(raw):>16} ! {error}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
