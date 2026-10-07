// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Sectop",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Sectop",
            path: "Sources/Sectop",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
