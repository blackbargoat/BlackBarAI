// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "BlackBarAI",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "BlackBarAI", path: "Sources/BlackBarAI")
    ]
)
