// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EthscriptionNames",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        // Library product that other packages and apps can import
        .library(
            name: "EthscriptionNames",
            targets: ["EthscriptionNames"]
        ),
    ],
    dependencies: [],
    targets: [
        // Main library target
        .target(
            name: "EthscriptionNames",
            dependencies: [],
            path: "Sources/EthscriptionNames"
        ),
        // Test target
        .testTarget(
            name: "EthscriptionNamesTests",
            dependencies: ["EthscriptionNames"],
            path: "Tests/EthscriptionNamesTests"
        ),
    ]
)
