// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "dayone-unlocked",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "dayone-unlocked",
            path: "Sources/dayone-unlocked",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("LocalAuthentication"),
            ]
        ),
    ]
)
