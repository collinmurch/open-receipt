import SwiftUI

struct ReceiptLibraryListRow: View {
  let receipt: ReceiptSummary
  var recognition: ReceiptRecognition?
  let onOpen: () -> Void
  let onDelete: () -> Void

  var body: some View {
    Button {
      guard !receipt.isUnavailable else { return }
      onOpen()
    } label: {
      ReceiptLibraryRow(receipt: receipt, recognition: recognition)
    }
    .buttonStyle(.plain)
    .contextMenu {
      if recognition == nil {
        Button("Delete Receipt", systemImage: "trash", role: .destructive) {
          onDelete()
        }
      }
    }
  }
}

struct ReceiptLibraryRow: View {
  let receipt: ReceiptSummary
  /// The active read of this receipt, which the row follows as it streams.
  var recognition: ReceiptRecognition?

  var body: some View {
    HStack(spacing: 14) {
      ReceiptMonogramTile(
        style: receipt.backgroundStyle,
        initials: recognition == nil && receipt.recognitionStatus == .succeeded
          ? receipt.merchantName.flatMap(ReceiptMonogram.initials) : nil,
        systemImage: tileSymbol)

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

      if recognition != nil {
        ProgressView()
      } else if let total = receipt.total {
        Text(total, format: .currency(code: displayCurrency))
          .font(.body.monospacedDigit())
          .foregroundStyle(.primary)
      } else {
        Image(systemName: receipt.isUnavailable ? "exclamationmark.triangle" : "arrow.clockwise")
          .foregroundStyle(.secondary)
      }
    }
    .contentShape(.rect)
  }

  private var tileSymbol: String {
    if recognition != nil { return "text.viewfinder" }
    if receipt.isUnavailable { return "exclamationmark.triangle" }
    return "receipt"
  }

  private var title: String {
    if let recognition { return recognition.preview.merchantName ?? "Reading Receipt" }
    if receipt.isUnavailable { return "Unavailable Receipt" }
    if receipt.recognitionStatus != .succeeded { return "Unprocessed Receipt" }
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
    if receipt.recognitionStatus != .succeeded { return "Needs Retry" }
    if let localDate = receipt.localDate,
      let formattedDate = ReceiptLibraryDateFormatter.dayTitle(localDate: localDate)
    {
      return formattedDate
    }
    return receipt.capturedAt.formatted(.dateTime.month(.wide).day())
  }

  private var displayCurrency: String {
    guard let currency = receipt.currency, currency.count == 3 else { return "USD" }
    return currency
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
          } else {
            Image(systemName: systemImage)
              .font(.subheadline.weight(.semibold))
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
