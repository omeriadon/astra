// swift-tools-version: 6.0
import PackageDescription

/// Foundation-only contracts shared by the main app and system integrations.
/// Keep AppKit, SwiftUI, WebKit, persistence and App Intents out of this target.
let package = Package(
    name: "AstraSystemKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "AstraSystemKit", targets: ["AstraSystemKit"])],
    targets: [
        .target(name: "AstraSystemKit"),
        .testTarget(name: "AstraSystemKitTests", dependencies: ["AstraSystemKit"]),
    ]
)
