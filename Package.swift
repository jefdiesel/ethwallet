// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EthWallet",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "EthWalletCore",
            targets: ["EthWalletCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/web3swift-team/web3swift.git", from: "3.3.0"),
    ],
    targets: [
        .target(
            name: "EthWalletCore",
            dependencies: [
                .product(name: "web3swift", package: "web3swift"),
            ],
            path: "Shared"
        ),
        .testTarget(
            name: "EthWalletTests",
            dependencies: ["EthWalletCore"],
            path: "Tests"
        ),
    ]
)
