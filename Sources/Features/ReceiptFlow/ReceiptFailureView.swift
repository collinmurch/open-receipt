import SwiftUI

/// A receipt that couldn't be read or hasn't been read yet. Reading again waits while the reading
/// limit is reached, and the receipt can always be entered by hand.
struct ReceiptFailureView: View {
  let failure: ReceiptFlowModel.Failure
  /// The receipt's colors, which tint its buttons as they do on the rest of the receipt.
  let backgroundStyle: ReceiptBackgroundStyle?
  let onRetry: () -> Void
  let onEnterManually: () -> Void
  @State private var isUnlockPresented = false
  @Environment(\.colorScheme) private var colorScheme
  @Environment(ReceiptRecognitionCenter.self) private var recognitions
  @Environment(ReadingAccess.self) private var access

  var body: some View {
    Group {
      if isLocked {
        locked
      } else {
        standard
      }
    }
    .tint(backgroundStyle?.accentColor(for: colorScheme))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .unlimitedReadingSheet(isPresented: $isUnlockPresented, onUnlock: onRetry)
  }

  /// Reading this receipt needs a free read, and they are all used.
  private var isLocked: Bool {
    failure.usesFreeRead && !access.isUnlocked && access.freeReadsLeft == 0
  }

  private var standard: some View {
    ContentUnavailableView {
      Label(failure.title, systemImage: failure.systemImage)
    } description: {
      Text(failure.description)
    } actions: {
      VStack(spacing: 12) {
        if let retry = failure.retry {
          Button(retryTitle(retry), action: onRetry)
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(backgroundStyle?.prominentColor)
            .disabled(retry.readsReceipt && !recognitions.canReadNow)
          if retry.readsReceipt, let readingNote, readingNote != failure.description {
            Text(readingNote)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
        manualEntryButton
      }
    }
  }

  private var locked: some View {
    ContentUnavailableView {
      Label("Free Reads Used", systemImage: "lock.fill")
        .symbolRenderingMode(.hierarchical)
    } description: {
      Text(lockedDescription)
    } actions: {
      VStack(spacing: 12) {
        Button("Unlock Unlimited Reading") { isUnlockPresented = true }
          .buttonStyle(.glassProminent)
          .controlSize(.large)
          .tint(backgroundStyle?.prominentColor)
        manualEntryButton
        Text("One-time purchase. No subscription.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding(.top, 4)
      }
    }
  }

  private var lockedDescription: String {
    let reason =
      isRescan
      ? "Unlock unlimited reading to read this receipt again."
      : "This receipt is saved. Unlock unlimited reading to read it, or enter its items yourself."
    return "You’ve used all \(ReadingAccess.freeReadLimit) free reads. \(reason)"
  }

  private var isRescan: Bool {
    guard case .recognize(let recognition) = failure.retry else { return false }
    return recognition.isRescan
  }

  @ViewBuilder
  private var manualEntryButton: some View {
    if failure.allowsManualEntry {
      Button(failure.manualEntryTitle, action: onEnterManually)
        .buttonStyle(.glass)
    }
  }

  private func retryTitle(_ retry: ReceiptFlowModel.Failure.Retry) -> String {
    switch retry {
    case .read: "Read Receipt"
    case .create, .load, .store, .recognize: "Try Again"
    }
  }

  private var readingNote: String? {
    switch recognitions.modelStatus {
    case .limitReached(let resetDate, _):
      resetDate.map { "Reading is available again \(DeferredReceiptRead.resumption(at: $0))." }
        ?? "Reading is available again later."
    case .unavailable(let reason):
      reason
    case .available, .approachingLimit:
      freeReadsNote
    }
  }

  private var freeReadsNote: String? {
    guard failure.usesFreeRead, !access.isUnlocked else { return nil }
    return "\(access.freeReadsLeftDescription)."
  }
}
