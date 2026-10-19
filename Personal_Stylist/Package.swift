// swift-tools-version: 5.9
import PackageDescription

// Host-side checks for the wire contracts and API client; no simulator or external packages.
let package = Package(
    name: "StylistCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "StylistCore", targets: ["StylistCore"])],
    targets: [
        .target(name: "StylistCore", path: "Core"),
        .testTarget(name: "StylistCoreTests", dependencies: ["StylistCore"], path: "Tests", exclude: ["NativeTests.swift"])
    ]
)
