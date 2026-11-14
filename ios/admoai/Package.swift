// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "admoai",
    platforms: [
        .iOS("12.0")
    ],
    products: [
        .library(name: "admoai", targets: ["admoai"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "admoai",
            dependencies: []
        )
    ]
)
