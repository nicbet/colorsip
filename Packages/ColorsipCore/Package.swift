// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ColorsipCore",
    platforms: [.macOS("15.8")],
    products: [
        .library(name: "ColorsipCore", targets: ["ColorsipCore"])
    ],
    targets: [
        .target(
            name: "ColorsipCore",
            resources: [
                // meodai/color-name-list v14.54.2 (MIT). See README "Third-party".
                .copy("Resources/colornames.csv"),
                .copy("Resources/color-name-list-LICENSE"),
                // tailwindlabs/tailwindcss v4.1.18 (MIT). See README "Third-party".
                .copy("Resources/tailwind-v4.1.18-theme.css"),
                .copy("Resources/tailwindcss-LICENSE"),
            ]
        ),
        .testTarget(name: "ColorsipCoreTests", dependencies: ["ColorsipCore"])
    ]
)
