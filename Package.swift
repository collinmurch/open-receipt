// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "open-receipt",
    platforms: [
        .iOS("27.0"),
        .macOS("27.0")
    ],
    products: [
        .library(name: "ReceiptKit", targets: ["ReceiptKit"]),
        .executable(name: "ReceiptLab", targets: ["ReceiptLab"])
    ],
    targets: [
        .target(
            name: "ReceiptKit",
            path: "Sources",
            exclude: ["App", "Features", "Models", "Services", "Utilities"],
            sources: ["ReceiptCore"]
        ),
        .executableTarget(
            name: "ReceiptLab",
            dependencies: ["ReceiptKit"],
            path: "Tools/ReceiptLab"
        ),
        .testTarget(
            name: "ReceiptKitTests",
            dependencies: ["ReceiptKit"],
            path: "Tests"
        ),
        .testTarget(
            name: "ReceiptLabTests",
            dependencies: ["ReceiptLab", "ReceiptKit"],
            path: "ToolTests"
        )
    ]
)
