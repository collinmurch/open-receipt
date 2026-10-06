import SwiftUI

/// Opens a receipt from a person's page. A link creates its destination along with the link, on
/// every update of the page, so the receipt's model, which reads the whole receipt, is only made
/// here once the link is followed.
struct PersonReceiptDestination: View {
  let input: ReceiptFlowInput

  var body: some View {
    ReceiptFlowView(input: input)
  }
}

/// A receipt on a person's page, with what they owe on it in place of the receipt's total.
struct PersonReceiptRow: View {
  let receipt: PersonReceipt

  var body: some View {
    HStack(spacing: 12) {
      ReceiptMonogramTile(
        style: receipt.summary.backgroundStyle,
        initials: receipt.summary.merchantName.flatMap(ReceiptMonogram.initials),
        systemImage: "receipt")
      VStack(alignment: .leading, spacing: 2) {
        Text(receipt.summary.merchantTitle)
          .lineLimit(1)
        if let date {
          Text(date)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 8)
      owedValue
    }
  }

  @ViewBuilder
  private var owedValue: some View {
    if let owed = receipt.owed {
      Text(owed, format: .currency(code: receipt.currency))
        .font(.body.monospacedDigit())
        .fontWeight(.semibold)
        .foregroundStyle(abs(owed) < 0.005 ? Color.secondary : Color.orange)
        .accessibilityLabel(
          "Owes \(owed.formatted(.currency(code: receipt.currency)))")
    } else {
      ShareTotalText(amount: nil, currency: receipt.currency)
    }
  }

  private var date: String? {
    receipt.summary.localDate.flatMap { ReceiptLibraryDateFormatter.formatted(localDate: $0) }
  }
}
