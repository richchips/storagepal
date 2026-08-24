// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StoragePal",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StoragePal", targets: ["StoragePal"])
    ],
    targets: [
        .executableTarget(
            name: "StoragePal",
            path: "Sources/StoragePal"
        ),
        .testTarget(
            name: "StoragePalTests",
            dependencies: ["StoragePal"],
            path: "Tests/StoragePalTests"
        )
    ]
)
