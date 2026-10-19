// swift-tools-version:5.9
// Tools version 5.9 builds in Swift 5 language mode, even on the Swift 6 toolchain.
import PackageDescription

let package = Package(
    name: "Strata",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Strata", path: "Sources/Strata"),
    ]
)
