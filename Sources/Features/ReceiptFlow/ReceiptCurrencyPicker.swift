import SwiftUI

struct ReceiptCurrencyPicker: View {
  @Binding var selection: String
  let backgroundStyle: ReceiptBackgroundStyle
  @State private var searchText = ""
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  private let catalog = CurrencyCatalog.current

  var body: some View {
    List {
      if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Section("Common") {
          ForEach(catalog.common) { currency in
            currencyRow(currency)
          }
        }

        Section("All Currencies") {
          ForEach(catalog.other) { currency in
            currencyRow(currency)
          }
        }
      } else {
        ForEach(searchResults) { currency in
          currencyRow(currency)
        }
      }
    }
    .receiptBackground(backgroundStyle)
    .tint(backgroundStyle.accentColor(for: colorScheme))
    .navigationTitle("Currency")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $searchText, prompt: "Search currencies")
  }

  private var searchResults: [CurrencyOption] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return catalog.searchOrder.filter {
      $0.code.localizedCaseInsensitiveContains(query)
        || $0.name.localizedCaseInsensitiveContains(query)
    }
  }

  private func currencyRow(_ currency: CurrencyOption) -> some View {
    Button {
      selection = currency.code
      dismiss()
    } label: {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(currency.name)
            .foregroundStyle(.primary)
          Text(currency.code)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if currency.code == selection.uppercased() {
          Image(systemName: "checkmark")
            .fontWeight(.semibold)
        }
      }
      .contentShape(.rect)
    }
  }
}

private struct CurrencyCatalog: Sendable {
  static let current: Self = {
    let currencies = Locale.commonISOCurrencyCodes.map { code in
      CurrencyOption(
        code: code,
        name: Locale.current.localizedString(forCurrencyCode: code) ?? code)
    }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    let currenciesByCode = Dictionary(uniqueKeysWithValues: currencies.map { ($0.code, $0) })
    let common = ["USD", "EUR", "GBP", "MXN", "JPY"].compactMap { currenciesByCode[$0] }
    let commonCodes = Set(common.map(\.code))
    let other = currencies.filter { !commonCodes.contains($0.code) }
    return Self(common: common, other: other, searchOrder: common + other)
  }()

  let common: [CurrencyOption]
  let other: [CurrencyOption]
  let searchOrder: [CurrencyOption]
}

private struct CurrencyOption: Identifiable, Sendable {
  let code: String
  let name: String

  var id: String { code }
}
