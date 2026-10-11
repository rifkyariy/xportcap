// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Xportcap",
    platforms: [.macOS(.v15)],
    targets: [.executableTarget(name: "Xportcap", path: "Sources", swiftSettings: [.swiftLanguageMode(.v5)])]
)
