// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Glance",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/quassum/SwiftUI-Tooltip.git", from: "1.3.1"),
    ],
    targets: [
        .executableTarget(
            name: "Glance",
            dependencies: [
                .product(name: "SwiftUITooltip", package: "SwiftUI-Tooltip"),
            ],
            resources: [
                .process("Assets.xcassets"),
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "GlanceTests",
            dependencies: ["Glance"]
        ),
    ]
)
