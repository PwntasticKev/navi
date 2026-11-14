// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NaviPad",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "NaviPad", targets: ["NaviPad"]),
    ],
    targets: [
        .target(name: "NaviPad"),
        .testTarget(name: "NaviPadTests", dependencies: ["NaviPad"]),
    ]
)
