// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EmblemCore",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "EmblemCore", targets: ["EmblemCore"])],
    targets: [.target(name: "EmblemCore")]
)
