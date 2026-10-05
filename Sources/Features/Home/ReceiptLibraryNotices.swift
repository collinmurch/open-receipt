import SwiftUI

/// How many free reads are left, shown once the first one is used. Tapping it offers the
/// purchase.
struct FreeReadsNotice: View {
  let onUnlock: () -> Void
  @Environment(ReadingAccess.self) private var access
  @ScaledMetric(relativeTo: .headline) private var ringSize: CGFloat = 36

  var body: some View {
    Button(action: onUnlock) {
      HStack(spacing: 14) {
        indicator
          .frame(width: ringSize, height: ringSize)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
          Text(detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.forward")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityHint("Shows the unlimited reading purchase")
  }

  @ViewBuilder
  private var indicator: some View {
    let left = access.freeReadsLeft
    if left == 0 {
      Image(systemName: "lock.fill")
        .font(.title3)
        .foregroundStyle(.tint)
    } else {
      ZStack {
        Circle()
          .stroke(.tint.opacity(0.2), lineWidth: 4)
        Circle()
          .trim(from: 0, to: Double(left) / Double(ReadingAccess.freeReadLimit))
          .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
          .rotationEffect(.degrees(-90))
        Text("\(left)")
          .font(.subheadline.weight(.semibold).monospacedDigit())
          .contentTransition(.numericText(value: Double(left)))
      }
      .animation(.smooth, value: left)
    }
  }

  private var title: String {
    access.freeReadsLeft == 0
      ? "Free Reads Used" : access.freeReadsLeftDescription.localizedCapitalized
  }

  private var detail: String {
    access.freeReadsLeft == 0
      ? "Unlock unlimited reading, or enter receipts yourself."
      : "Unlock unlimited reading with one purchase."
  }
}

/// Persistent status for receipt reading, shown before a person adds a receipt rather than after.
struct ReceiptModelNotice: View {
  let status: ReceiptModelStatus
  let onIncreaseLimit: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(message, systemImage: systemImage)
        .font(.footnote)
        .foregroundStyle(.secondary)
      if canIncreaseLimit {
        Button("Increase Limit", action: onIncreaseLimit)
          .font(.footnote.weight(.semibold))
      }
    }
  }

  private var message: String {
    switch status {
    case .available:
      return ""
    case .approachingLimit:
      return "You’re close to today’s limit for reading receipts."
    case .limitReached(let resetDate, _):
      let resumption = resetDate.map { DeferredReceiptRead.resumption(at: $0) } ?? "later"
      return
        "Today’s reading limit is reached. New receipts are saved and read automatically \(resumption)."
    case .unavailable(let reason):
      return "\(reason) You can still enter receipts manually."
    }
  }

  private var systemImage: String {
    switch status {
    case .available, .approachingLimit: "gauge.with.dots.needle.67percent"
    case .limitReached: "hourglass"
    case .unavailable: "exclamationmark.triangle"
    }
  }

  private var canIncreaseLimit: Bool {
    switch status {
    case .approachingLimit(let canIncreaseLimit), .limitReached(_, let canIncreaseLimit):
      canIncreaseLimit
    case .available, .unavailable:
      false
    }
  }
}
