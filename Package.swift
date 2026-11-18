// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StatuspageMenuBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "StatuspageMenuBar",
            path: "Sources"
        )
    ]
)
