import Foundation

extension Double {
  /// Whether the amount can be requested: a finite amount above zero.
  var isRequestable: Bool {
    isFinite && self > 0
  }

  /// The amount with two decimal places and a period, as payment links expect in every locale.
  var paymentLinkAmount: String {
    String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), self)
  }
}
