// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Breather",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Breather",
            path: "Sources/Breather"
        )
    ]
)
