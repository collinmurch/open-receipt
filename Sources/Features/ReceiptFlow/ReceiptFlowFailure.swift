import Foundation

extension ReceiptFlowModel {
  /// Why a receipt isn't showing its review, and the ways out.
  struct Failure {
    enum Retry {
      case create(UUID)
      case load(UUID)
      case store(ReceiptScan)
      case recognize(ReceiptRecognition)
      /// Reads a stored scan that hasn't been read.
      case read(UUID)

      /// Whether retrying sends the scan to the model.
      var readsReceipt: Bool {
        switch self {
        case .recognize, .read: true
        case .create, .load, .store: false
        }
      }
    }

    var title = "Couldn’t Read Receipt"
    var systemImage = "exclamationmark.triangle"
    /// Whether something went wrong, as opposed to a receipt that is waiting to be read.
    var isError = true
    let description: String
    let retry: Retry?
    /// Whether the stored scan can be kept and its values entered by hand.
    var allowsManualEntry = false
    var manualEntryTitle = "Enter Manually"
    /// Whether trying again reads the receipt under a new free read, so it needs unlimited
    /// reading once they are used.
    var usesFreeRead = false
  }
}

extension ReceiptFlowModel.Failure {
  private static let backToReceipt = "Back to Receipt"

  /// A stored receipt that hasn't been read: put off until the reading limit resets, failed, or
  /// never tried.
  static func unread(_ document: ReceiptDocument) -> Self {
    let recognition = document.recognition
    if let deferredUntil = recognition.deferredUntil {
      return .waiting(
        DeferredReceiptRead.description(until: deferredUntil), retry: .read(document.id))
    }
    if recognition.status == .failed {
      return Self(
        description: recognition.failureMessage ?? "The receipt couldn’t be read.",
        retry: .read(document.id),
        allowsManualEntry: true)
    }
    return Self(
      title: "Receipt Not Read",
      systemImage: "doc.text.viewfinder",
      isError: false,
      description: "Read this receipt to fill in its items and totals, or enter them yourself.",
      retry: .read(document.id),
      allowsManualEntry: true,
      usesFreeRead: true)
  }

  /// A read that failed, or that is waiting for the reading limit to reset when `isDeferred`.
  static func readFailed(_ message: String, retry: Retry?, isDeferred: Bool) -> Self {
    isDeferred
      ? .waiting(message, retry: retry)
      : Self(description: message, retry: retry, allowsManualEntry: true)
  }

  /// A rescan held back because reading the new pages needs unlimited reading.
  static func rescanNotRead(retry: Retry) -> Self {
    Self(
      title: "New Pages Not Read",
      systemImage: "doc.text.viewfinder",
      isError: false,
      description: "Read this receipt again to update it from its new pages.",
      retry: retry,
      allowsManualEntry: true,
      manualEntryTitle: backToReceipt,
      usesFreeRead: true)
  }

  /// A rescan that failed, which can go back to the values already stored.
  static func rescanFailed(_ message: String, retry: Retry?) -> Self {
    Self(
      title: "Couldn’t Read Receipt Again",
      description: message,
      retry: retry,
      allowsManualEntry: true,
      manualEntryTitle: backToReceipt)
  }

  private static func waiting(_ description: String, retry: Retry?) -> Self {
    Self(
      title: "Waiting to Read",
      systemImage: "hourglass",
      isError: false,
      description: description,
      retry: retry,
      allowsManualEntry: true)
  }
}
