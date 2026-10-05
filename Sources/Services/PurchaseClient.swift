import StoreKit
import SwiftUI

enum PurchaseOutcome: Equatable, Sendable {
  case purchased
  /// The purchase waits for approval, such as Ask to Buy.
  case pending
  case cancelled
}

enum PurchaseError: LocalizedError {
  case productUnavailable
  case nothingToRestore

  var errorDescription: String? {
    switch self {
    case .productUnavailable: "The App Store couldn’t be reached. Try again in a moment."
    case .nothingToRestore:
      "No purchase of unlimited reading was found for this Apple Account."
    }
  }
}

/// The App Store purchase of unlimited reading. Debug uses a stand-in that never reaches the App
/// Store.
struct PurchaseClient: Sendable {
  /// Whether this Apple Account has a verified purchase that wasn't refunded or revoked.
  let isEntitled: @Sendable () async -> Bool
  /// Yields whenever a transaction arrives outside a purchase in the app, such as a purchase on
  /// another device, an approved Ask to Buy, or a refund.
  let updates: @Sendable () -> AsyncStream<Void>
  /// The purchase's localized price, such as "$2.99".
  let displayPrice: @Sendable () async throws -> String
  /// Buys unlimited reading. Pass the `purchase` action from the view that offers it, so the App
  /// Store's confirmation is presented over that view.
  let purchase: @MainActor @Sendable (PurchaseAction?) async throws -> PurchaseOutcome
  /// Asks the App Store for this account's purchases again. Only call it when someone asks to.
  let restore: @Sendable () async throws -> Void

  static let unlimitedReadingID = "com.collinmurch.openreceipt.unlimited"
}

extension PurchaseClient {
  static let live = PurchaseClient(
    isEntitled: {
      for await result in Transaction.currentEntitlements(for: unlimitedReadingID) {
        if case .verified(let transaction) = result, transaction.revocationDate == nil {
          return true
        }
      }
      return false
    },
    updates: {
      .producing { continuation in
        for await result in Transaction.updates {
          if case .verified(let transaction) = result {
            await transaction.finish()
          }
          continuation.yield()
        }
      }
    },
    displayPrice: { try await product(unlimitedReadingID).displayPrice },
    purchase: { action in
      let product = try await product(unlimitedReadingID)
      let result: Product.PurchaseResult
      if let action {
        result = try await action(product)
      } else {
        result = try await product.purchase()
      }
      switch result {
      case .success(.verified(let transaction)):
        await transaction.finish()
        return .purchased
      case .success(.unverified(_, let error)):
        throw error
      case .pending:
        return .pending
      case .userCancelled:
        return .cancelled
      @unknown default:
        return .cancelled
      }
    },
    restore: { try await AppStore.sync() })

  private static func product(_ id: String) async throws -> Product {
    guard let product = try await Product.products(for: [id]).first else {
      throw PurchaseError.productUnavailable
    }
    return product
  }

  /// A purchase kept in memory, for tests, previews, and screenshots. Purchasing ends with
  /// `outcome`, and a completed purchase is entitled from then on.
  static func fixed(
    isEntitled: Bool,
    outcome: PurchaseOutcome = .purchased
  ) -> PurchaseClient {
    let entitlement = Locked(isEntitled)
    return PurchaseClient(
      isEntitled: { entitlement.value },
      updates: { .finished },
      displayPrice: { "$2.99" },
      purchase: { _ in
        if outcome == .purchased { entitlement.value = true }
        return outcome
      },
      restore: {})
  }

  #if DEBUG
    /// A purchase that unlocks at once and is remembered in user defaults. Launch with
    /// `-DebugUnlimitedReading YES` to start unlocked.
    static let debug = PurchaseClient(
      isEntitled: { UserDefaults.standard.bool(forKey: PurchaseClient.debugUnlockedKey) },
      updates: { .finished },
      displayPrice: { "$2.99" },
      purchase: { _ in
        UserDefaults.standard.set(true, forKey: PurchaseClient.debugUnlockedKey)
        return .purchased
      },
      restore: {})

    private static let debugUnlockedKey = "DebugUnlimitedReading"
  #endif

  /// The App Store in Release builds, and a stand-in in Debug builds.
  static var standard: PurchaseClient {
    #if DEBUG
      return .debug
    #else
      return .live
    #endif
  }
}
