// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "dayone-mcp-plus",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "dayone-mcp-plus",
            path: "Sources/dayone-mcp-plus",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("LocalAuthentication"),
            ]
        ),
    ]
)
