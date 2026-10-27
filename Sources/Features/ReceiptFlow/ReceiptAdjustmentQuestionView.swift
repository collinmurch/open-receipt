import SwiftUI

/// Asks about tax or tip that a read didn't find, before the receipt is split. A segmented
/// control offers the usual answers and a custom amount or percentage, shown in a row like the
/// one the receipt edits it in.
struct ReceiptAdjustmentQuestionView: View {
  @Bindable var draft: ReceiptDraft
  let adjustment: ReceiptTotalAdjustment
  private let presets: [AdjustmentPreset]
  @State private var choice: AdjustmentChoice
  @State private var customAmount = 0.0
  @FocusState private var focusedField: ReceiptAmountField?
  @Environment(\.colorScheme) private var colorScheme

  init(draft: ReceiptDraft, adjustment: ReceiptTotalAdjustment) {
    self.draft = draft
    self.adjustment = adjustment
    let presets = Self.presets(for: adjustment, in: draft)
    self.presets = presets
    _choice = State(initialValue: presets.middle.map(AdjustmentChoice.preset) ?? .custom)
  }

  var body: some View {
    ScrollView {
      content
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }
    .defaultScrollAnchor(.center, for: .alignment)
    // The content rarely scrolls, so swiping can't dismiss the keyboard. Tapping anywhere the
    // controls don't handle does instead.
    .contentShape(.rect)
    .onTapGesture { focusedField = nil }
    .scrollBounceBehavior(.basedOnSize)
    .scrollDismissesKeyboard(.interactively)
    .keyboardNavigation($focusedField, through: [field])
    .receiptBottomBar { addButton }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Skip") {
          focusedField = nil
          draft.stopAsking(about: adjustment)
        }
      }
    }
    .tint(draft.backgroundStyle.accentColor(for: colorScheme))
    .navigationTitle(draft.merchantName.isEmpty ? "Receipt" : draft.merchantName)
    .navigationBarTitleDisplayMode(.inline)
  }

  /// The question and its answer, centered in the space above the buttons.
  private var content: some View {
    VStack(spacing: 32) {
      header
      VStack(spacing: 16) {
        if !presets.isEmpty {
          AdjustmentChoicePicker(
            title: "\(adjustment.title) Amount", presets: presets,
            choice: choiceBinding.animation(.settle))
        }
        VStack(alignment: .leading, spacing: 8) {
          amountRow
          if let detail {
            Text(detail)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .padding(.horizontal, 20)
          }
        }
      }
    }
  }

  /// The amount, drawn like a row of the receipt's list.
  private var amountRow: some View {
    AdjustmentAmountRow(
      title: adjustment.title, amount: Binding(get: { amount }, set: { customAmount = $0 }),
      isCustom: choice == .custom, currencyCode: currency, focus: $focusedField, field: field
    ) {
      Text(adjustment.title)
    }
    .padding(.horizontal, 20)
    .frame(minHeight: 56)
    .background(
      Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28, style: .continuous)
    )
    .choosesCustomAmount(choiceBinding)
  }

  private var field: ReceiptAmountField {
    .adjustment(adjustment)
  }

  /// The choice, where choosing custom starts from the amount shown.
  private var choiceBinding: Binding<AdjustmentChoice> {
    Binding(
      get: { choice },
      set: { newChoice in
        if newChoice == .custom { customAmount = amount }
        choice = newChoice
      }
    ).focusingCustom(field, in: $focusedField)
  }

  private var amount: Double {
    guard case .preset(let preset) = choice else { return customAmount }
    return preset.amount
  }

  private var header: some View {
    VStack(spacing: 14) {
      Image(systemName: systemImage)
        .font(.system(size: 54))
        .foregroundStyle(.tint)
        .symbolRenderingMode(.hierarchical)
      VStack(spacing: 6) {
        Text(title)
          .font(.title.bold())
        Text(message)
          .foregroundStyle(.secondary)
      }
      .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
  }

  private var addButton: some View {
    ReceiptActionButton(
      title: "Add \(adjustment.title)",
      systemImage: "checkmark",
      tint: draft.backgroundStyle.prominentColor
    ) {
      focusedField = nil
      if adjustment == .tip, let percentage = choice.percentage {
        draft.confirmTip(percentage: percentage)
      } else {
        draft.confirm(adjustment, amount: amount)
      }
    }
    .disabled(amount <= 0)
    .opacity(amount > 0 ? 1 : 0.5)
  }

  private static func presets(
    for adjustment: ReceiptTotalAdjustment,
    in draft: ReceiptDraft
  ) -> [AdjustmentPreset] {
    switch adjustment {
    case .tax:
      draft.impliedTax.map { [AdjustmentPreset(title: "Auto (From Total)", amount: $0)] } ?? []
    case .tip:
      draft.tipPresets
    case .savings:
      []
    }
  }

  private var detail: String? {
    if adjustment == .tax, case .preset = choice {
      return "The total is \(formatted(amount)) more than the items."
    }
    if adjustment == .tip {
      return draft.tipCaption(for: amount, percentage: choice.percentage).map {
        "\(formatted(amount)) is \($0)."
      }
    }
    let base = draft.itemsTotal
    guard base > 0, amount > 0 else { return nil }
    let percentage = (amount / base * 100).formatted(
      .percent.scale(1).precision(.fractionLength(0...1)))
    return "\(formatted(amount)) is \(percentage) of \(formatted(base)) in items."
  }

  private var title: String {
    switch adjustment {
    case .tax: "Tax Not Found"
    case .tip: "Did You Tip?"
    case .savings: "Any Savings?"
    }
  }

  private var message: String {
    switch adjustment {
    case .tax: "This receipt doesn’t show any tax. Add it so it’s split with everything else."
    case .tip: "Add a tip so it’s split along with the bill."
    case .savings: "Add savings so everyone shares them."
    }
  }

  private var systemImage: String {
    switch adjustment {
    case .tax: "doc.text.magnifyingglass"
    case .tip: "heart.circle"
    case .savings: "tag"
    }
  }

  private var currency: String {
    draft.displayCurrency
  }

  private func formatted(_ amount: Double) -> String {
    amount.formatted(.currency(code: currency))
  }
}
