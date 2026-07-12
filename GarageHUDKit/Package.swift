// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GarageHUDKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "GarageHUDKit",
            targets: ["GarageHUDKit"]
        )
    ],
    targets: [
        .target(
            name: "GarageHUDKit",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        ),
        .testTarget(
            name: "GarageHUDKitTests",
            dependencies: ["GarageHUDKit"]
        )
    ]
)
