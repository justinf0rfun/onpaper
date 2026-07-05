// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "onpaper",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "OnPaperCore",
            targets: ["OnPaperCore"]
        ),
        .library(
            name: "OnPaperDestinations",
            targets: ["OnPaperDestinations"]
        ),
        .executable(
            name: "OnPaperApp",
            targets: ["OnPaperApp"]
        )
    ],
    dependencies: [
        .package(path: "../opennook")
    ],
    targets: [
        .target(name: "OnPaperCore"),
        .target(name: "OnPaperDestinations"),
        .executableTarget(
            name: "OnPaperApp",
            dependencies: [
                "OnPaperCore",
                .product(name: "NookApp", package: "opennook")
            ]
        ),
        .testTarget(
            name: "OnPaperCoreTests",
            dependencies: ["OnPaperCore"]
        ),
        .testTarget(
            name: "OnPaperDestinationsTests",
            dependencies: ["OnPaperDestinations"]
        )
    ]
)
