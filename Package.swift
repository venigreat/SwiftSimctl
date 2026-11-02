// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "SwiftSimctl",
    platforms: [
        .iOS(.v11),
        .tvOS(.v11),
        .macOS(.v10_12)
    ],
    products: [
        .executable(name: "SimctlCLI", targets: ["SimctlCLI"]),
        .library(name: "Simctl", targets: ["Simctl"])
    ],
    dependencies: [
        .package(name: "swift-argument-parser", url: "https://github.com/apple/swift-argument-parser", from: "1.2.2"),
        .package(name: "Swifter",  url: "https://github.com/httpswift/swifter.git", from: "1.5.0")
    ],
    targets: [
        .target(name: "SimctlShared"),
        .target(name: "SimctlServerCore", dependencies: ["SimctlShared", "Swifter"]),
        .target(name: "SimctlCLI", dependencies: ["SimctlShared", "SimctlServerCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .target(name: "Simctl", dependencies: ["SimctlShared"]),
        .testTarget(name: "SimctlTests", dependencies: ["Simctl", "SimctlShared"]),
        .testTarget(name: "SimctlServerCoreTests", dependencies: ["SimctlServerCore", "SimctlShared", "Swifter"])
    ],
    swiftLanguageVersions: [.v5]
)
