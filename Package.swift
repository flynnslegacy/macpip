// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MacPiP",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MacPiP",
            path: "Sources/MacPiP"
        )
    ]
)
