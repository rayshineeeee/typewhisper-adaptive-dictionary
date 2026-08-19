// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AdaptiveDictionary",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AdaptiveDictionaryCore", targets: ["AdaptiveDictionaryCore"]),
    ],
    targets: [
        .target(name: "AdaptiveDictionaryCore"),
        .testTarget(
            name: "AdaptiveDictionaryCoreTests",
            dependencies: ["AdaptiveDictionaryCore"]
        ),
    ]
)
