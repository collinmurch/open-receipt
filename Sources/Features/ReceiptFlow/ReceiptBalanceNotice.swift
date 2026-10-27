import SwiftUI

/// Explains one step of a receipt that doesn't add up: what the receipt prints, what its parts
/// come to, the likely cause, and how to fix it.
struct ReceiptBalanceNotice: Equatable {
  enum Kind: Hashable {
    /// The items don't come to the printed subtotal.
    case items
    /// The items and the total agree, but the printed subtotal doesn't.
    case subtotal
    /// The subtotal and adjustments don't come to the printed total.
    case total
  }

  enum Action: Hashable {
    case addItem(Double)
    case setSubtotal(Double)
    case setTotal(Double)
  }

  let kind: Kind
  let title: String
  let message: String
  let actions: [Action]

  /// The amount field the notice is about.
  var field: ReceiptAmountField {
    kind == .total ? .total : .subtotal
  }

  /// The first step of `draft` that doesn't add up, from the items down to the total. Fixing it
  /// reveals the next one, so the subtotal is explained before the total.
  @MainActor
  static func notice(for draft: ReceiptDraft) -> ReceiptBalanceNotice? {
    let balance = draft.balance
    let currency = draft.displayCurrency
    func formatted(_ amount: Double) -> String {
      amount.formatted(.currency(code: currency))
    }
    let subtotalUnits = balance.subtotalDifferenceUnits
    let totalUnits = balance.totalDifferenceUnits

    if subtotalUnits != 0, let printed = balance.printedSubtotal,
      let calculated = balance.calculatedSubtotal
    {
      if subtotalUnits == -totalUnits {
        return ReceiptBalanceNotice(
          kind: .subtotal,
          title: "Subtotal doesn’t match",
          message: "The items and the total agree, but the subtotal reads "
            + "\(formatted(printed)). It may have been misread.",
          actions: [.setSubtotal(calculated)])
      }
      let difference = abs(balance.subtotalDifference)
      let isShort = subtotalUnits > 0
      return ReceiptBalanceNotice(
        kind: .items,
        title: isShort
          ? "Items are \(formatted(difference)) short"
          : "Items are \(formatted(difference)) over",
        message: "\(itemsPhrase(for: balance.placement)) come to \(formatted(calculated)), "
          + "but the receipt’s subtotal is \(formatted(printed)). "
          + (isShort
            ? "An item may be missing or misread." : "An item may be extra or misread."),
        actions: isShort
          ? [.addItem(difference), .setSubtotal(calculated)] : [.setSubtotal(calculated)])
    }
    guard totalUnits != 0 else { return nil }
    let difference = abs(balance.totalDifference)
    let isHigher = totalUnits > 0
    return ReceiptBalanceNotice(
      kind: .total,
      title: isHigher
        ? "Total is \(formatted(difference)) higher"
        : "Total is \(formatted(difference)) lower",
      message: "\(partsPhrase(of: draft, balance: balance)) come to "
        + "\(formatted(balance.calculatedTotal)), "
        + "but the receipt’s total is \(formatted(draft.total)). "
        + (isHigher
          ? "A fee or charge may be missing."
          : "A discount may be missing, or an amount misread."),
      actions: [.setTotal(balance.calculatedTotal)])
  }

  private static func itemsPhrase(for placement: ReceiptBalance.SavingsPlacement) -> String {
    switch (placement.isInItems, placement.isInSubtotal) {
    case (true, false): "The items before savings"
    case (false, true): "The items after savings"
    default: "The items"
    }
  }

  /// The amounts the total is made of, such as "The subtotal, tax, and tip".
  @MainActor
  private static func partsPhrase(of draft: ReceiptDraft, balance: ReceiptBalance) -> String {
    var parts = [balance.printedSubtotal == nil ? "items" : "subtotal"]
    if draft.adjustments.contains(.tax) { parts.append("tax") }
    if draft.adjustments.contains(.tip) { parts.append("tip") }
    if draft.adjustments.contains(.savings), balance.subtractsSavingsFromSubtotal {
      parts.append("savings")
    }
    return "The \(parts.formatted(.list(type: .and)))"
  }
}

/// A notice's explanation and its fixes, shown in a row below the receipt's totals.
struct ReceiptBalanceNoticeRow: View {
  let notice: ReceiptBalanceNotice
  let currencyCode: String
  let perform: (ReceiptBalanceNotice.Action) -> Void

  var body: some View {
    VStack(spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Image(systemName: "plusminus.circle.fill")
          .font(.body)
          .foregroundStyle(.orange)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text(notice.title)
            .font(.subheadline.weight(.semibold))
          Text(notice.message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      actions
        .frame(maxWidth: .infinity)
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .contain)
  }

  /// The fixes side by side on one line each, or stacked and wrapping when that doesn't fit.
  private var actions: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) { actionButtons }
        .lineLimit(1)
      VStack(spacing: 8) { actionButtons }
        .multilineTextAlignment(.center)
    }
  }

  private var actionButtons: some View {
    ForEach(Array(notice.actions.enumerated()), id: \.element) { index, action in
      let isPrimary = index == 0
      Button {
        perform(action)
      } label: {
        if case .addItem = action {
          Label(title(of: action), systemImage: "plus")
            .labelStyle(.titleAndIcon)
        } else {
          Text(title(of: action))
        }
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.capsule)
      .controlSize(.small)
      .fontWeight(isPrimary ? .semibold : .regular)
      .tint(isPrimary ? Color.orange : Color.gray)
      .foregroundStyle(isPrimary ? Color.orange : Color.primary)
    }
  }

  private func title(of action: ReceiptBalanceNotice.Action) -> String {
    switch action {
    case .addItem: "Add Item"
    case .setSubtotal(let amount): "Set Subtotal to \(formatted(amount))"
    case .setTotal(let amount): "Set Total to \(formatted(amount))"
    }
  }

  private func formatted(_ amount: Double) -> String {
    amount.formatted(.currency(code: currencyCode))
  }
}
