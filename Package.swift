// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SpacePin",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "SpacePin",
            targets: ["SpacePin"]
        ),
    ],
    targets: [
        .target(
            name: "SpacePinCore"
        ),
        .executableTarget(
            name: "SpacePin",
            dependencies: ["SpacePinCore"]
        ),
        .testTarget(
            name: "SpacePinCoreTests",
            dependencies: ["SpacePinCore"]
        ),
    ]
)
