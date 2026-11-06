// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CleanSlateCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "CleanSlateCore", targets: ["CleanSlateCore"])],
    targets: [
        .target(name: "CleanSlateCore"),
        .testTarget(name: "CleanSlateCoreTests", dependencies: ["CleanSlateCore"])
    ]
)
