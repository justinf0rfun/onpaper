// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "onpaper",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "OnPaperDestinations",
            targets: ["OnPaperDestinations"]
        )
    ],
    targets: [
        .target(name: "OnPaperDestinations"),
        .testTarget(
            name: "OnPaperDestinationsTests",
            dependencies: ["OnPaperDestinations"]
        )
    ]
)
