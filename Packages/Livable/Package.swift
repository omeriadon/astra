// swift-tools-version: 6.3
import PackageDescription
let package = Package(
    name: "Livable",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "Livable", targets: ["Livable"])],
    targets: [.target(name: "Livable", resources: [.process("Shaders")])],
    swiftLanguageModes: [.v6]
)
