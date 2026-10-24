// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AnixartKit",
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17)],
    products: [
        .library(name: "AnixartKit", targets: ["AnixartKit"])
    ],
    targets: [
        .target(name: "AnixartKit"),
        .testTarget(
            name: "AnixartKitTests",
            dependencies: ["AnixartKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
