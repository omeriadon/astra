// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AstraAutomationCore",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "AstraAutomationCore", targets: ["AstraAutomationCore"]),
    ],
    targets: [
        .target(name: "AstraAutomationCore"),
        .testTarget(name: "AstraAutomationCoreTests", dependencies: ["AstraAutomationCore"]),
    ]
)
