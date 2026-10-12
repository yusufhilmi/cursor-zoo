// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CursorZoo",
    platforms: [.macOS(.v14)],
    targets: [
        // Prototypes for the private CoreGraphics cursor calls.
        .target(name: "CGSPrivate", path: "Sources/CGSPrivate"),
        .executableTarget(
            name: "CursorZoo",
            dependencies: ["CGSPrivate"],
            path: "Sources/CursorZoo",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("CoreGraphics")]
        )
    ]
)
