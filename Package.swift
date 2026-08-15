// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MedxElite",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "MedxElite",
            targets: ["MedxElite"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MedxElite",
            path: "MedxElite",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
