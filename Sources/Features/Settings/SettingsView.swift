import SwiftUI

struct SettingsView: View {
  @AppStorage(PaymentSettings.defaultMethodKey) private var defaultPaymentMethod =
    PaymentSettings.initialDefaultMethod
  @AppStorage(CurrencySettings.defaultCodeKey) private var defaultCurrencyCode =
    CurrencySettings.initialDefaultCode
  @AppStorage(AdjustmentSplitSettings.defaultMethodKey) private var defaultAdjustmentSplitMethod =
    AdjustmentSplitSettings.initialDefaultMethod
  @Environment(ReadingAccess.self) private var access

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
        VStack(alignment: .leading, spacing: 12) {
          if access.channel.isTesting {
            Text(access.channel.title)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.orange)
              .textCase(nil)
          }
          Text("Default Payment Method")
        }
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

      UnlimitedReadingSection()

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

/// The purchase of unlimited reading, and tools for testing it in TestFlight and Debug builds.
private struct UnlimitedReadingSection: View {
  @State private var isUnlockPresented = false
  @State private var isRestoring = false
  @State private var restoreMessage: String?
  @Environment(ReadingAccess.self) private var access

  var body: some View {
    Section {
      if access.isUnlocked {
        Label("Unlocked", systemImage: "checkmark.seal.fill")
      } else {
        Button("Unlock Unlimited Reading", systemImage: "infinity") {
          isUnlockPresented = true
        }
      }
      Button(action: restore) {
        HStack {
          Label("Restore Purchase", systemImage: "arrow.clockwise")
          if isRestoring {
            Spacer()
            ProgressView()
          }
        }
      }
      .disabled(isRestoring)
    } header: {
      Text("Unlimited Reading")
    } footer: {
      Text(footer)
    }
    .unlimitedReadingSheet(isPresented: $isUnlockPresented)
    .alert(
      "Restore Purchase",
      isPresented: Binding(
        get: { restoreMessage != nil },
        set: { if !$0 { restoreMessage = nil } }),
      presenting: restoreMessage,
      actions: { _ in Button("OK", role: .cancel) {} },
      message: { Text($0) })

    if access.isTesting {
      PurchaseTestingSection()
    }
  }

  private var footer: String {
    if access.isUnlocked {
      return "Every receipt can be read. Thanks for your support."
    }
    return "\(access.freeReadsLeftDescription). One purchase unlocks unlimited reads."
  }

  private func restore() {
    isRestoring = true
    Task {
      defer { isRestoring = false }
      do {
        try await access.restore()
        restoreMessage = "Unlimited reading is unlocked."
      } catch {
        restoreMessage = error.localizedDescription
      }
    }
  }
}

/// Tools for testing the purchase, shown outside the production App Store.
private struct PurchaseTestingSection: View {
  @State private var isRemoveConfirmationPresented = false
  @AppStorage(SampleReceipts.key) private var storedSampleReceipts: Bool?
  @Environment(ReadingAccess.self) private var access

  var body: some View {
    Section {
      Toggle("Sample Receipts", isOn: sampleReceipts)
      Stepper(value: freeReadsLeft, in: 0...ReadingAccess.freeReadLimit) {
        LabeledContent(
          "Free Reads Left", value: access.isUnlocked ? "Unlimited" : "\(access.freeReadsLeft)")
      }
      .disabled(access.isUnlocked)
      if access.isUnlocked {
        Button("Remove Purchase", role: .destructive) { isRemoveConfirmationPresented = true }
      }
    } header: {
      Text("Testing")
    } footer: {
      Text("Sample receipts read without Private Cloud Compute.")
    }
    .alert("Remove Purchase?", isPresented: $isRemoveConfirmationPresented) {
      Button("Remove", role: .destructive) {
        Task { await access.removePurchaseForTesting() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "This build reads receipts as if unlimited reading was never bought. Buy or restore it to get it back."
      )
    }
  }

  private var sampleReceipts: Binding<Bool> {
    Binding(
      get: { storedSampleReceipts ?? SampleReceipts.isOnByDefault(in: access.channel) },
      set: { storedSampleReceipts = $0 })
  }

  private var freeReadsLeft: Binding<Int> {
    Binding(
      get: { access.freeReadsLeft },
      set: { access.setFreeReadsLeftForTesting($0) })
  }
}

enum AppLinks {
  static let privacyPolicy = URL(
    string: "https://github.com/collinmurch/open-receipt/blob/main/PRIVACY.md")!
  static let support = URL(string: "https://github.com/collinmurch/open-receipt/issues")!
}
