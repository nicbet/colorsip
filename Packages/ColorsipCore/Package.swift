// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ColorsipCore",
    platforms: [.macOS("15.8")],
    products: [
        .library(name: "ColorsipCore", targets: ["ColorsipCore"])
    ],
    targets: [
        .target(name: "ColorsipCore"),
        .testTarget(name: "ColorsipCoreTests", dependencies: ["ColorsipCore"])
    ]
)
