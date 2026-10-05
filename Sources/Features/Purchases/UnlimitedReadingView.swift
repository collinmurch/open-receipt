import SwiftUI

extension View {
  /// Offers the one-time purchase of unlimited reading. `onUnlock` runs once reading unlocks,
  /// whether by a purchase here, a restored purchase, or an approval that arrives while it is
  /// open.
  func unlimitedReadingSheet(
    isPresented: Binding<Bool>,
    onUnlock: @escaping () -> Void = {}
  ) -> some View {
    sheet(isPresented: isPresented) {
      UnlimitedReadingView(onUnlock: onUnlock)
    }
  }
}

/// The paywall for unlimited reading.
struct UnlimitedReadingView: View {
  let onUnlock: () -> Void
  @State private var isPurchasing = false
  @State private var isRestoring = false
  @State private var isPending = false
  @State private var priceErrorDescription: String?
  @State private var errorDescription: String?
  @Environment(ReadingAccess.self) private var access
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ScrollView {
          VStack(spacing: 32) {
            header
            features
          }
          .padding(.horizontal, 28)
          .padding(.top, 24)
          .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        purchaseControls
          .padding(.horizontal, 24)
          .padding(.bottom, 12)
      }
      .background { ReceiptLibraryBackground() }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(role: .close) { dismiss() }
        }
      }
    }
    .interactiveDismissDisabled(isPurchasing)
    .task { await loadPrice() }
    .onChange(of: access.isUnlocked) { _, isUnlocked in
      guard isUnlocked else { return }
      onUnlock()
      dismiss()
    }
    .errorAlert("Couldn’t Complete Purchase", message: $errorDescription)
  }

  private var header: some View {
    VStack(spacing: 14) {
      Image(systemName: "doc.text.viewfinder")
        .font(.system(size: 54))
        .foregroundStyle(.tint)
        .symbolRenderingMode(.hierarchical)
      VStack(spacing: 6) {
        Text("Unlimited Reading")
          .font(.largeTitle.bold())
        Text(summary)
          .font(.body)
          .foregroundStyle(.secondary)
      }
      .multilineTextAlignment(.center)
    }
  }

  private var summary: String {
    guard access.freeReadsLeft > 0 else {
      return
        "You’ve used your \(ReadingAccess.freeReadLimit) free reads. Unlock reading for every receipt after this one."
    }
    return
      "You have \(access.freeReadsLeftDescription). Unlock reading for every receipt after that."
  }

  private var features: some View {
    VStack(alignment: .leading, spacing: 20) {
      feature(
        "Read every receipt",
        detail: "Scan or import as many receipts as you like.",
        systemImage: "infinity")
      feature(
        "Pay once",
        detail: "One purchase, kept forever. No subscription.",
        systemImage: "checkmark.seal")
      feature(
        "Shared with your family",
        detail: "Family Sharing unlocks reading for everyone in your family.",
        systemImage: "person.2")
      feature(
        "Still private",
        detail: "No account. Receipts stay on your device.",
        systemImage: "lock.shield")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func feature(_ title: String, detail: String, systemImage: String) -> some View {
    Label {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    } icon: {
      Image(systemName: systemImage)
        .font(.title3)
        .foregroundStyle(.tint)
        .frame(width: 32)
    }
  }

  private var purchaseControls: some View {
    VStack(spacing: 12) {
      if isPending {
        Label(
          "Waiting for approval. Reading unlocks once the purchase is approved.",
          systemImage: "hourglass"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      } else if let priceErrorDescription {
        Text(priceErrorDescription)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        Button("Try Again") { Task { await loadPrice() } }
          .buttonStyle(.glass)
      }

      Button(action: purchase) {
        ZStack {
          Text(purchaseTitle)
            .opacity(isPurchasing ? 0 : 1)
          if isPurchasing {
            ProgressView()
          }
        }
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 32)
      }
      .buttonStyle(.glassProminent)
      .disabled(access.displayPrice == nil || isPurchasing || isRestoring)
      .screenshotHighlight("unlimited-reading-purchase")

      Text("One-time purchase. No subscription.")
        .font(.footnote)
        .foregroundStyle(.secondary)

      Button(action: restore) {
        if isRestoring {
          ProgressView()
        } else {
          Text("Restore Purchase")
        }
      }
      .font(.footnote.weight(.semibold))
      .disabled(isPurchasing || isRestoring)
    }
  }

  private var purchaseTitle: String {
    access.displayPrice.map { "Unlock for \($0)" } ?? "Unlock"
  }

  private func loadPrice() async {
    guard access.displayPrice == nil else { return }
    priceErrorDescription = nil
    do {
      try await access.loadPrice()
    } catch {
      priceErrorDescription = error.localizedDescription
    }
  }

  private func purchase() {
    isPurchasing = true
    Task {
      defer { isPurchasing = false }
      do {
        isPending = try await access.purchase() == .pending
      } catch {
        errorDescription = error.localizedDescription
      }
    }
  }

  private func restore() {
    isRestoring = true
    Task {
      defer { isRestoring = false }
      do {
        try await access.restore()
      } catch {
        errorDescription = error.localizedDescription
      }
    }
  }
}
