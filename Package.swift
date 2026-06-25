// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LabyrinthCanvas",
    platforms: [
        .iOS(.v16),
        .macCatalyst(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "LabyrinthCanvas",
            targets: ["LabyrinthCanvas"]
        )
    ],
    targets: [
        .target(
            name: "LabyrinthCanvas",
            resources: [
                .process("Rendering/Shaders.metal")
            ]
        ),
        .testTarget(
            name: "LabyrinthCanvasTests",
            dependencies: ["LabyrinthCanvas"]
        )
    ]
)
