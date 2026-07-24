// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GlancePane",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GlancePane", targets: ["GlancePane"])
    ],
    targets: [
        .executableTarget(
            name: "GlancePane",
            path: "Sources/GlancePane"
        )
    ]
)
