// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Wedge",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Wedge",
            path: "Sources/Wedge"
        ),
        .executableTarget(
            name: "WedgeIcon",
            path: "Sources/WedgeIcon"
        )
    ],
    swiftLanguageModes: [.v6]
)
