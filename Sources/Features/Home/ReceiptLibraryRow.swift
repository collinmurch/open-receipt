import SwiftUI

struct ReceiptLibraryRow: View {
  let receipt: ReceiptSummary
  /// The active read of this receipt, which the row follows as it streams.
  var recognition: ReceiptRecognition?
  /// The namespace the receipt zooms out of when it opens from this row.
  var transitionNamespace: Namespace.ID?

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
        .contentTransition(.numericText())
    } else {
      Image(systemName: statusSymbol)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var monogramTile: some View {
    let tile = ReceiptMonogramTile(
      style: receipt.backgroundStyle,
      initials: recognition == nil && receipt.recognitionStatus == .succeeded
        ? receipt.merchantName.flatMap(ReceiptMonogram.initials) : nil,
      systemImage: tileSymbol)
    if let transitionNamespace {
      tile.matchedTransitionSource(id: receipt.id, in: transitionNamespace)
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
    let merchant = receipt.merchantName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return merchant.isEmpty ? "Receipt" : merchant
  }

  private var subtitle: String {
    if let recognition {
      if recognition.status == .waitingForConnection { return "Waiting for connection" }
      let count = recognition.preview.items.count
      guard count > 0 else { return "Reading…" }
      let items = String(AttributedString(localized: "^[\(count) item](inflect: true)").characters)
      return "Reading · \(items)"
    }
    if receipt.isUnavailable { return "This receipt cannot be opened." }
    if receipt.recognitionStatus != .succeeded {
      if let deferredUntil = receipt.deferredUntil {
        return DeferredReceiptRead.status(until: deferredUntil)
      }
      return receipt.recognitionStatus == .failed ? "Couldn’t Read" : "Not Read"
    }
    if let localDate = receipt.localDate,
      let formattedDate = ReceiptLibraryDateFormatter.dayTitle(localDate: localDate)
    {
      return formattedDate
    }
    return receipt.capturedAt.formatted(.dateTime.month(.abbreviated).day())
  }
}

/// A small rounded tile carrying a receipt's theme, the only place its color appears in the library.
struct ReceiptMonogramTile: View {
  let style: ReceiptBackgroundStyle
  let initials: String?
  let systemImage: String
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    RoundedRectangle(cornerRadius: 11, style: .continuous)
      .fill(
        LinearGradient(
          colors: style.colors(for: colorScheme),
          startPoint: .topLeading,
          endPoint: .bottomTrailing)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .strokeBorder(.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 0.5)
      }
      .overlay {
        Group {
          if let initials {
            Text(initials)
              .font(.system(.subheadline, design: .rounded).weight(.bold))
              .transition(.opacity.combined(with: .scale(scale: 0.8)))
          } else {
            Image(systemName: systemImage)
              .font(.subheadline.weight(.semibold))
              .contentTransition(.symbolEffect(.replace))
              .transition(.opacity.combined(with: .scale(scale: 0.8)))
          }
        }
        .foregroundStyle(style.accentColor(for: colorScheme))
      }
      .frame(width: 42, height: 42)
      .accessibilityHidden(true)
  }
}

enum ReceiptMonogram {
  /// Up to two initials from the first words of a merchant name that start with a letter or digit.
  static func initials(for name: String) -> String? {
    let letters =
      name
      .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "/" })
      .compactMap { $0.first(where: { $0.isLetter || $0.isNumber }) }
      .prefix(2)
    guard !letters.isEmpty else { return nil }
    return String(letters).uppercased()
  }
}
