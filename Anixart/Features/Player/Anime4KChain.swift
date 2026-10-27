// Generated from ThirdParty/Anime4K by Tools/convert-anime4k.py.
// Do not edit -- see Anime4KFilter.swift for the runtime that reads this.

import CoreGraphics

/// One pass of an Anime4K chain, as the shader's own directives describe it.
struct Anime4KPass: Sendable {
    /// The Metal function this pass compiled to.
    let function: String
    /// Which images it reads, by the names the shader uses. `MAIN` is the
    /// picture as it stands; the rest are earlier passes' output.
    let binds: [String]
    /// Where its output goes. `MAIN` replaces the picture.
    let save: String
    /// Whose size the output takes, and times what.
    let sizedLike: String
    let scale: CGFloat
}

enum Anime4KChain {
    static let restore: [Anime4KPass] = [
        Anime4KPass(
            function: "a4k_restore_0",
            binds: ["MAIN"],
            save: "conv2d_tf",
            sizedLike: "MAIN",
            scale: 1.0
        ),
        Anime4KPass(
            function: "a4k_restore_1",
            binds: ["conv2d_tf"],
            save: "conv2d_1_tf",
            sizedLike: "conv2d_tf",
            scale: 1.0
        ),
        Anime4KPass(
            function: "a4k_restore_2",
            binds: ["conv2d_1_tf"],
            save: "conv2d_2_tf",
            sizedLike: "conv2d_1_tf",
            scale: 1.0
        ),
        Anime4KPass(
            function: "a4k_restore_3",
            binds: ["MAIN", "conv2d_2_tf"],
            save: "MAIN",
            sizedLike: "conv2d_2_tf",
            scale: 1.0
        ),
    ]

    static let upscaleX2: [Anime4KPass] = [
        Anime4KPass(
            function: "a4k_upscaleX2_0",
            binds: ["MAIN"],
            save: "conv2d_tf",
            sizedLike: "MAIN",
            scale: 1.0
        ),
        Anime4KPass(
            function: "a4k_upscaleX2_1",
            binds: ["conv2d_tf"],
            save: "conv2d_1_tf",
            sizedLike: "conv2d_tf",
            scale: 1.0
        ),
        Anime4KPass(
            function: "a4k_upscaleX2_2",
            binds: ["conv2d_1_tf"],
            save: "conv2d_2_tf",
            sizedLike: "conv2d_1_tf",
            scale: 1.0
        ),
        Anime4KPass(
            function: "a4k_upscaleX2_3",
            binds: ["conv2d_2_tf"],
            save: "conv2d_last_tf",
            sizedLike: "conv2d_2_tf",
            scale: 1.0
        ),
        Anime4KPass(
            function: "a4k_upscaleX2_4",
            binds: ["MAIN", "conv2d_last_tf"],
            save: "MAIN",
            sizedLike: "conv2d_last_tf",
            scale: 2.0
        ),
    ]

}
