import Observation
import UIKit

extension NewReceiptSource {
  /// The home screen quick action type for this source, as declared in `Info.plist`.
  var quickActionType: String {
    "\(Bundle.main.bundleIdentifier ?? "").new-receipt.\(quickActionName)"
  }

  init?(quickActionType type: String) {
    guard let source = Self.allCases.first(where: { $0.quickActionType == type }) else {
      return nil
    }
    self = source
  }

  private var quickActionName: String {
    switch self {
    case .scan: "scan"
    case .importPhotos: "import"
    case .create: "create"
    }
  }
}

/// Home screen quick actions that start a new receipt, waiting for the library to take them.
@MainActor
@Observable
final class NewReceiptQuickActions {
  /// Quick actions arrive through the scene delegate, which UIKit creates, so they share one
  /// instance with the app.
  static let shared = NewReceiptQuickActions()

  var pending: NewReceiptSource?

  /// Queues `item` if it starts a new receipt, returning whether it did.
  @discardableResult
  func perform(_ item: UIApplicationShortcutItem) -> Bool {
    guard let source = NewReceiptSource(quickActionType: item.type) else { return false }
    pending = source
    return true
  }
}
