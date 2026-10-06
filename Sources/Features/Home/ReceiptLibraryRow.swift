import SwiftUI

struct ReceiptLibraryRow: View {
  let receipt: ReceiptSummary
  /// The active read of this receipt, which the row follows as it streams.
  var recognition: ReceiptRecognition?
  /// Where the receipt zooms out of when it opens from this row.
  var transition: (id: HomeZoomSource, namespace: Namespace.ID)?
  /// When the receipt leaves Recently Deleted, for a row describing a deleted receipt. Such a row
  /// counts down to it in place of the receipt's reading status.
  var expiresAt: Date?

  var body: some View {
    HStack(spacing: 14) {
      monogramTile

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.body.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        if let unavailableDescription = receipt.unavailableDescription {
          Text(unavailableDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }

      Spacer(minLength: 8)

      trailingStatus
    }
    .contentShape(.rect)
    .animation(.smooth(duration: 0.3), value: recognition == nil)
    .animation(.smooth(duration: 0.3), value: receipt)
  }

  @ViewBuilder
  private var trailingStatus: some View {
    if recognition != nil {
      ProgressView()
    } else if let total = receipt.total {
      Text(total, format: .currency(code: ReceiptCurrency.displayCode(receipt.currency)))
        .font(.body.monospacedDigit())
        .foregroundStyle(.primary)
        .contentTransition(.numericText(value: total))
    } else if expiresAt == nil {
      Image(systemName: statusSymbol)
        .foregroundStyle(.secondary)
        .contentTransition(.symbolEffect(.replace))
    }
  }

  @ViewBuilder
  private var monogramTile: some View {
    let tile = ReceiptMonogramTile(
      style: receipt.backgroundStyle,
      initials: recognition == nil && receipt.recognitionStatus == .succeeded
        ? receipt.merchantName.flatMap(ReceiptMonogram.initials) : nil,
      systemImage: tileSymbol)
    if let transition {
      tile.matchedTransitionSource(id: transition.id, in: transition.namespace)
    } else {
      tile
    }
  }

  private var statusSymbol: String {
    if receipt.isUnavailable { return "exclamationmark.triangle" }
    return receipt.deferredUntil == nil ? "arrow.clockwise" : "hourglass"
  }

  private var tileSymbol: String {
    if recognition != nil { return "text.viewfinder" }
    if receipt.isUnavailable { return "exclamationmark.triangle" }
    return "receipt"
  }

  private var title: String {
    if let recognition { return recognition.preview.merchantName ?? "Reading Receipt" }
    if receipt.isUnavailable { return "Unavailable Receipt" }
    if receipt.recognitionStatus != .succeeded { return "Unread Receipt" }
    return receipt.merchantTitle
  }

  private var subtitle: String {
    if let expiresAt {
      let days = max(1, Int((expiresAt.timeIntervalSinceNow / 86_400).rounded(.up)))
      return "\(dateDescription) · \(String(inflecting: "^[\(days) day](inflect: true)")) left"
    }
    if let recognition {
      if recognition.status == .waitingForConnection { return "Waiting for connection" }
      let count = recognition.preview.items.count
      guard count > 0 else { return "Reading…" }
      return "Reading · \(String(inflecting: "^[\(count) item](inflect: true)"))"
    }
    if receipt.isUnavailable { return "This receipt cannot be opened." }
    if receipt.recognitionStatus != .succeeded {
      if let deferredUntil = receipt.deferredUntil {
        return DeferredReceiptRead.status(until: deferredUntil)
      }
      return receipt.recognitionStatus == .failed ? "Couldn’t Read" : "Not Read"
    }
    return dateDescription
  }

  private var dateDescription: String {
    if receipt.recognitionStatus == .succeeded, let localDate = receipt.localDate,
      let formattedDate = ReceiptLibraryDateFormatter.dayTitle(localDate: localDate)
    {
      return formattedDate
    }
    return receipt.capturedAt.formatted(.dateTime.month(.abbreviated).day())
  }
}
