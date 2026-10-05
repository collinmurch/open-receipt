import Foundation
import StoreKit

/// Where the running build came from. Development and TestFlight builds show testing tools and
/// can read sample receipts; App Store builds never do.
enum BuildChannel: Equatable, Sendable {
  /// A Debug build, a simulator build, or a Release build run with a StoreKit configuration file.
  case development
  /// TestFlight and App Review, where purchases go through the sandbox.
  case testFlight
  case appStore

  /// Whether testing tools are shown and their settings apply.
  var isTesting: Bool {
    self != .appStore
  }

  /// The build's name in testing builds.
  var title: String {
    switch self {
    case .development: "Debug Build"
    case .testFlight: "TestFlight Build"
    case .appStore: "App Store Build"
    }
  }

  /// The channel found at launch. Until then it is App Store in Release builds, so nothing meant
  /// for testing applies early.
  static var current: BuildChannel {
    get { resolved.value }
    set { resolved.value = newValue }
  }

  private static let resolved = Locked(Self.compiled)

  /// Debug and simulator builds are always development. Other builds start as the App Store.
  private static var compiled: BuildChannel {
    #if DEBUG || targetEnvironment(simulator)
      return .development
    #else
      return .appStore
    #endif
  }

  /// Finds the channel and records it as `current`. A Release build whose origin the App Store
  /// can't verify counts as the App Store.
  static func resolve() async -> BuildChannel {
    var channel = compiled
    if channel == .appStore,
      let result = try? await AppTransaction.shared,
      case .verified(let transaction) = result
    {
      switch transaction.environment {
      case .sandbox: channel = .testFlight
      case .xcode: channel = .development
      default: channel = .appStore
      }
    }
    current = channel
    return channel
  }
}
