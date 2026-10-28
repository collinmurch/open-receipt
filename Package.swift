// swift-tools-version: 6.2
import PackageDescription

let approachableConcurrency: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
  name: "open-receipt",
  platforms: [
    .iOS("27.0"),
    .macOS("27.0"),
  ],
  products: [
    .library(name: "ReceiptKit", targets: ["ReceiptKit"]),
    .executable(name: "ReceiptLab", targets: ["ReceiptLab"]),
    .executable(name: "ScreenshotComposer", targets: ["ScreenshotComposer"]),
  ],
  targets: [
    .target(
      name: "ReceiptKit",
      path: "Sources/ReceiptCore",
      swiftSettings: approachableConcurrency
    ),
    .executableTarget(
      name: "ReceiptLab",
      dependencies: ["ReceiptKit"],
      path: "Tools/ReceiptLab",
      exclude: ["ReceiptLab.entitlements"],
      swiftSettings: approachableConcurrency
    ),
    .executableTarget(
      name: "ScreenshotComposer",
      path: "Tools/Screenshots/Composer",
      swiftSettings: approachableConcurrency + [.defaultIsolation(MainActor.self)]
    ),
    .testTarget(
      name: "ReceiptKitTests",
      dependencies: ["ReceiptKit"],
      path: "Tests/ReceiptKit",
      swiftSettings: approachableConcurrency
    ),
    .testTarget(
      name: "ReceiptLabTests",
      dependencies: ["ReceiptLab", "ReceiptKit"],
      path: "Tests/ReceiptLab",
      swiftSettings: approachableConcurrency
    ),
  ]
)
