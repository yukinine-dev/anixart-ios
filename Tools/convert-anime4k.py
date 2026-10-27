#!/usr/bin/env python3
"""Translate Anime4K's mpv shaders into Core Image Metal kernels.

The originals in `ThirdParty/Anime4K` are written for mpv's hook format: a file
is a run of passes, each with `//!HOOK`, `//!BIND`, `//!SAVE`, `//!WIDTH` and
`//!HEIGHT` directives, and a GLSL `hook()` body that reads its bound textures
through `NAME_tex`, `NAME_texOff`, `NAME_pos`, `NAME_size` and `NAME_pt`.

They are translated rather than rewritten because the bodies are weights --
eighteen thousand numbers across the two files. Anything hand-copied would be
wrong somewhere and impossible to update.

The one real difference is coordinates. mpv gives each pass normalised texture
coordinates; Core Image gives it a destination pixel and a `transform` into each
sampler's own space, and a pass whose output is twice the size of its input
cannot get that mapping from Core Image, because the two images sit in the same
working space at different scales. So every position here is computed from
`dest.coord()` and the sizes, which are passed in, and nothing is inferred.

    python3 Tools/convert-anime4k.py ThirdParty/Anime4K \
        Anixart/Resources/Shaders/Anime4K.ci.metal \
        Anixart/Features/Player/Anime4KChain.swift
"""

import pathlib
import re
import sys

# Source file -> the name the chain is known by in Swift.
CHAINS = [
    ("Anime4K_Restore_CNN_S.glsl", "restore"),
    ("Anime4K_Upscale_CNN_x2_S.glsl", "upscaleX2"),
]

GLSL_TYPES = [
    ("mat4(", "float4x4("),
    ("vec4(", "float4("),
    ("vec3(", "float3("),
    ("vec2(", "float2("),
    ("ivec2(", "int2("),
    ("ivec4(", "int4("),
    ("vec4 ", "float4 "),
    ("vec3 ", "float3 "),
    ("vec2 ", "float2 "),
    ("ivec2 ", "int2 "),
]


class Pass:
    def __init__(self):
        self.desc = ""
        self.binds = []
        self.save = "MAIN"
        self.width = None
        self.height = None
        self.when = None
        self.body = []


def parse(text: str) -> list[Pass]:
    passes: list[Pass] = []
    current: Pass | None = None

    for line in text.splitlines():
        if line.startswith("//!DESC"):
            current = Pass()
            current.desc = line[len("//!DESC"):].strip()
            passes.append(current)
            continue
        if current is None:
            continue  # the licence header
        if line.startswith("//!"):
            key, _, value = line[3:].partition(" ")
            value = value.strip()
            if key == "BIND":
                current.binds.append(value)
            elif key == "SAVE":
                current.save = value
            elif key == "WIDTH":
                current.width = value
            elif key == "HEIGHT":
                current.height = value
            elif key == "WHEN":
                current.when = value
            continue
        current.body.append(line)

    return passes


def scale_of(directive: str | None) -> tuple[str, float]:
    """`conv2d_last_tf.w 2 *` -> ("conv2d_last_tf", 2.0).

    Reverse Polish, and only ever a size followed by a constant multiply in
    these files. Anything else is refused rather than guessed at.
    """
    if directive is None:
        return ("MAIN", 1.0)
    tokens = directive.split()
    source = tokens[0].rsplit(".", 1)[0]
    if len(tokens) == 1:
        return (source, 1.0)
    if len(tokens) == 3 and tokens[2] == "*":
        return (source, float(tokens[1]))
    raise SystemExit(f"!! cannot read size directive: {directive!r}")


def translate(body: list[str], binds: list[str], prefix: str) -> str:
    text = "\n".join(body)

    # Longest first, so `X_texOff` is not half-eaten by `X_tex`.
    patterns: list[tuple[str, str]] = []
    for index, name in enumerate(binds):
        patterns += [
            (f"{name}_texOff(", f"{prefix}_off{index}("),
            (f"{name}_tex(", f"{prefix}_at{index}("),
            (f"{name}_pos", "npos"),
            (f"{name}_size", f"size{index}"),
            (f"{name}_pt", f"pt{index}"),
        ]
    patterns.sort(key=lambda pair: -len(pair[0]))

    for old, new in patterns:
        text = text.replace(old, new)
    for old, new in GLSL_TYPES:
        text = text.replace(old, new)

    # `hook()` becomes the kernel's body; its own `#define`s stay as they are.
    text = text.replace("float4 hook() {", "// --- body ---")
    lines = [line for line in text.splitlines() if line.strip()]
    if lines and lines[-1].strip() == "}":
        lines = lines[:-1]
    return "\n".join(lines)


def emit_metal(path: pathlib.Path, chains: list[tuple[str, list[Pass]]]) -> str:
    out: list[str] = []
    out.append("// Generated from ThirdParty/Anime4K by Tools/convert-anime4k.py.")
    out.append("// Do not edit: the bodies are trained weights, and the originals are")
    out.append("// upstream. MIT licensed -- see ThirdParty/Anime4K/LICENSE.")
    out.append("")
    out.append("#include <metal_stdlib>")
    out.append("#include <CoreImage/CoreImage.h>")
    out.append("")
    out.append("using namespace metal;")
    out.append("")

    for chain, passes in chains:
        for index, item in enumerate(passes):
            name = f"a4k_{chain}_{index}"
            prefix = name

            args = []
            for bind_index in range(len(item.binds)):
                args.append(f"coreimage::sampler t{bind_index}")
                args.append(f"float2 size{bind_index}")
            args.append("float2 destSize")
            args.append("coreimage::destination dest")

            out.append(f"// {item.desc}")
            out.append(f"// binds {', '.join(item.binds)} -> saves {item.save}")
            for bind_index in range(len(item.binds)):
                out.append(
                    f"#define {prefix}_at{bind_index}(nc) "
                    f"t{bind_index}.sample(t{bind_index}.transform((nc) * size{bind_index}))"
                )
                out.append(
                    f"#define {prefix}_off{bind_index}(o) "
                    f"t{bind_index}.sample(t{bind_index}.transform("
                    f"npos * size{bind_index} + (o)))"
                )
            out.append(f"extern \"C\" float4 {name}(")
            out.append("    " + ",\n    ".join(args))
            out.append(") {")
            out.append("    // Normalised position, which is what every mpv hook works in.")
            out.append("    float2 npos = dest.coord() / destSize;")
            for bind_index in range(len(item.binds)):
                out.append(f"    float2 pt{bind_index} = 1.0 / size{bind_index};")
                out.append(f"    (void)pt{bind_index};")
            out.append(translate(item.body, item.binds, prefix))
            out.append("}")
            for bind_index in range(len(item.binds)):
                out.append(f"#undef {prefix}_at{bind_index}")
                out.append(f"#undef {prefix}_off{bind_index}")
            # The source's own go_N macros are per-pass and must not leak.
            for macro in re.findall(r"#define\s+(go_\d+)", "\n".join(item.body)):
                out.append(f"#undef {macro}")
            out.append("")

    return "\n".join(out) + "\n"


def emit_swift(chains: list[tuple[str, list[Pass]]]) -> str:
    out: list[str] = []
    out.append("// Generated from ThirdParty/Anime4K by Tools/convert-anime4k.py.")
    out.append("// Do not edit -- see Anime4KFilter.swift for the runtime that reads this.")
    out.append("")
    out.append("import CoreGraphics")
    out.append("")
    out.append("/// One pass of an Anime4K chain, as the shader's own directives describe it.")
    out.append("struct Anime4KPass: Sendable {")
    out.append("    /// The Metal function this pass compiled to.")
    out.append("    let function: String")
    out.append("    /// Which images it reads, by the names the shader uses. `MAIN` is the")
    out.append("    /// picture as it stands; the rest are earlier passes' output.")
    out.append("    let binds: [String]")
    out.append("    /// Where its output goes. `MAIN` replaces the picture.")
    out.append("    let save: String")
    out.append("    /// Whose size the output takes, and times what.")
    out.append("    let sizedLike: String")
    out.append("    let scale: CGFloat")
    out.append("}")
    out.append("")
    out.append("enum Anime4KChain {")

    for chain, passes in chains:
        out.append(f"    static let {chain}: [Anime4KPass] = [")
        for index, item in enumerate(passes):
            source, scale = scale_of(item.width)
            binds = ", ".join(f"\"{bind}\"" for bind in item.binds)
            out.append("        Anime4KPass(")
            out.append(f"            function: \"a4k_{chain}_{index}\",")
            out.append(f"            binds: [{binds}],")
            out.append(f"            save: \"{item.save}\",")
            out.append(f"            sizedLike: \"{source}\",")
            out.append(f"            scale: {scale}")
            out.append("        ),")
        out.append("    ]")
        out.append("")

    out.append("}")
    return "\n".join(out) + "\n"


def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    source = pathlib.Path(sys.argv[1])
    metal_out = pathlib.Path(sys.argv[2])
    swift_out = pathlib.Path(sys.argv[3])

    chains: list[tuple[str, list[Pass]]] = []
    for filename, name in CHAINS:
        passes = parse((source / filename).read_text(encoding="utf-8"))
        if not passes:
            raise SystemExit(f"!! no passes found in {filename}")
        chains.append((name, passes))
        heights = [scale_of(item.height) for item in passes]
        widths = [scale_of(item.width) for item in passes]
        if heights != widths:
            raise SystemExit(f"!! {filename} scales width and height differently")
        print(f"{filename}: {len(passes)} passes")

    metal_out.write_text(emit_metal(metal_out, chains), encoding="utf-8")
    swift_out.write_text(emit_swift(chains), encoding="utf-8")
    print(f"wrote {metal_out} and {swift_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
