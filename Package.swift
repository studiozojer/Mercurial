// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Mercurial",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Mercurial",
            targets: ["Mercurial"]
        ),
    ],
    targets: [
        .target(
            name: "Mercurial"
        ),
        .testTarget(
            name: "MercurialTests",
            dependencies: ["Mercurial"]
        ),
    ]
)
