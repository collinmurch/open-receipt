import SwiftUI

struct PaymentMethodSettingsView: View {
  @AppStorage(PaymentSettings.defaultMethodKey) private var defaultPaymentMethodRawValue =
    PaymentSettings.initialDefaultMethod.rawValue

  var body: some View {
    Form {
      Section {
        Picker("Payment Method", selection: $defaultPaymentMethodRawValue) {
          ForEach(PaymentMethod.allCases) { method in
            Label {
              Text(method.title)
            } icon: {
              PaymentMethodIcon(method: method)
            }
            .tag(method.rawValue)
          }
        }
        .labelsHidden()
        .pickerStyle(.inline)
      } header: {
        Text("Default Payment Method")
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
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
  }
}

enum AppLinks {
  static let privacyPolicy = URL(
    string: "https://github.com/collinmurch/open-receipt/blob/main/PRIVACY.md")!
  static let support = URL(string: "https://github.com/collinmurch/open-receipt/issues")!
}
