import SwiftUI

struct SettingsView: View {
  @AppStorage(PaymentSettings.defaultMethodKey) private var defaultPaymentMethod =
    PaymentSettings.initialDefaultMethod
  @AppStorage(CurrencySettings.defaultCodeKey) private var defaultCurrencyCode =
    CurrencySettings.initialDefaultCode
  @AppStorage(AdjustmentSplitSettings.defaultMethodKey) private var defaultAdjustmentSplitMethod =
    AdjustmentSplitSettings.initialDefaultMethod

  var body: some View {
    Form {
      Section {
        Picker("Payment Method", selection: $defaultPaymentMethod) {
          ForEach(PaymentMethod.allCases) { method in
            Label {
              Text(method.title)
            } icon: {
              PaymentMethodIcon(method: method)
            }
            .tag(method)
          }
        }
        .labelsHidden()
        .pickerStyle(.inline)
      } header: {
        Text("Default Payment Method")
      }

      Section {
        NavigationLink {
          ReceiptCurrencyPicker(selection: $defaultCurrencyCode)
        } label: {
          LabeledContent(
            "Currency", value: ReceiptCurrency.localizedName(defaultCurrencyCode))
        }
      } header: {
        Text("Default Currency")
      } footer: {
        Text("New receipts start in this currency.")
      }

      Section {
        Picker("Split Tax/Tip", selection: $defaultAdjustmentSplitMethod) {
          ForEach(ReceiptAdjustmentSplitMethod.allCases) { method in
            Text(method.title)
              .tag(method)
          }
        }
        .pickerStyle(.menu)
      } header: {
        Text("Default Split")
      } footer: {
        Text("New receipts split tax and tip this way.")
      }

      Section {
        Link(destination: AppLinks.privacyPolicy) {
          Label("Privacy Policy", systemImage: "hand.raised")
        }
        Link(destination: AppLinks.support) {
          Label("Support", systemImage: "questionmark.circle")
        }
      } header: {
        Text("About")
      } footer: {
        Text(
          "Receipts and people stay on this device. Receipt images are read by Apple Intelligence using Private Cloud Compute."
        )
      }
    }
    .scrollContentBackground(.hidden)
    .background { ReceiptLibraryBackground() }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
  }
}

enum AppLinks {
  static let privacyPolicy = URL(
    string: "https://github.com/collinmurch/open-receipt/blob/main/PRIVACY.md")!
  static let support = URL(string: "https://github.com/collinmurch/open-receipt/issues")!
}
