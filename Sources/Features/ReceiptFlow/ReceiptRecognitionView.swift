import SwiftUI

/// A receipt while the model reads it. Rows appear as the model writes them, laid out like the
/// review list so the finished receipt takes their place without moving. While the read waits for
/// a connection, the receipt can be entered by hand instead.
struct ReceiptRecognitionView: View {
  let recognition: ReceiptRecognition
  let onEnterManually: () -> Void
  @ScaledMetric(relativeTo: .caption2) private var headerHeight = ParticipantStrip.baseHeight
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let preview = recognition.preview
    let currency = ReceiptCurrency.displayCode(preview.currency)

    List {
      Section("Items") {
        if preview.items.isEmpty {
          ForEach(0..<3, id: \.self) { _ in
            ReceiptRecognitionPlaceholderRow()
          }
        } else {
          ForEach(preview.items.indices, id: \.self) { index in
            ReceiptRecognitionItemRow(item: preview.items[index], currency: currency)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }
      }

      if let total = preview.total, total != 0 {
        Section {
          HStack {
            Text("Total")
            Spacer()
            Text(total, format: .currency(code: currency))
              .monospacedDigit()
              .contentTransition(.numericText(value: total))
          }
          .fontWeight(.semibold)
        }
        .transition(.opacity)
      }
    }
    .scrollContentBackground(.hidden)
    .animation(.smooth(duration: 0.4), value: preview.items.count)
    .animation(.smooth(duration: 0.4), value: preview.total)
    .safeAreaBar(edge: .top) {
      ReceiptRecognitionStatusBar(recognition: recognition, height: headerHeight)
        .receiptTopBarPadding()
    }
    .safeAreaBar(edge: .bottom) {
      GlassEffectContainer {
        if recognition.status == .waitingForConnection {
          ReceiptActionButton(
            title: recognition.isRescan ? "Back to Receipt" : "Enter Manually",
            systemImage: recognition.isRescan ? "arrow.uturn.backward" : "square.and.pencil",
            tint: recognition.backgroundStyle.prominentColor,
            action: onEnterManually)
        }
      }
      .padding(.bottom, 8)
      .animation(.bouncy(duration: 0.5, extraBounce: 0.1), value: recognition.status)
    }
    .tint(recognition.backgroundStyle.accentColor(for: colorScheme))
    .navigationTitle(title(for: preview))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func title(for preview: ReceiptParsePreview) -> String {
    preview.merchantName ?? "Reading Receipt"
  }
}

private struct ReceiptRecognitionStatusBar: View {
  let recognition: ReceiptRecognition
  let height: CGFloat

  var body: some View {
    HStack(spacing: 14) {
      ReceiptRecognitionThumbnail(
        image: recognition.thumbnail,
        isScanning: recognition.status == .reading
      )
      .frame(width: height * 0.5, height: height * 0.68)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.headline)
          .contentTransition(.opacity)
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .contentTransition(.numericText())
          .lineLimit(2)
      }

      Spacer(minLength: 0)

      if recognition.status == .waitingForConnection {
        Image(systemName: "wifi.exclamationmark")
          .font(.title3)
          .foregroundStyle(.secondary)
          .symbolEffect(.pulse)
      } else {
        ProgressView()
      }
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, minHeight: height)
    .glassEffect(in: .rect(cornerRadius: 22))
    .screenshotHighlight("receipt-reading-status")
    .animation(.smooth(duration: 0.3), value: recognition.status)
    .animation(.smooth(duration: 0.3), value: recognition.preview.items.count)
    .accessibilityElement(children: .combine)
  }

  private var title: String {
    switch recognition.status {
    case .reading: "Reading Receipt"
    case .waitingForConnection: "Waiting for Connection"
    case .saving, .finished: "Finishing Up"
    }
  }

  private var detail: String {
    let preview = recognition.preview
    switch recognition.status {
    case .waitingForConnection:
      return "Reading resumes when you’re back online."
    case .reading, .saving, .finished:
      guard !preview.items.isEmpty else {
        return String(
          AttributedString(localized: "^[\(recognition.pageCount) page](inflect: true)").characters)
      }
      let currency = ReceiptCurrency.displayCode(preview.currency)
      let items = String(
        AttributedString(localized: "^[\(preview.items.count) item](inflect: true)").characters)
      let sum = preview.itemTotal.formatted(.currency(code: currency))
      guard let total = preview.total, total != 0 else { return "\(items) · \(sum)" }
      return "\(items) · \(sum) of \(total.formatted(.currency(code: currency)))"
    }
  }
}

/// The first scanned page, with a light sweeping across it while the model reads.
private struct ReceiptRecognitionThumbnail: View {
  let image: CGImage?
  let isScanning: Bool
  @State private var sweeps = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(.secondary.opacity(0.15))
      .overlay {
        if let image {
          Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFill()
            .transition(.opacity)
        }
      }
      .overlay {
        if isScanning && !reduceMotion {
          GeometryReader { proxy in
            LinearGradient(
              colors: [.clear, .white.opacity(0.55), .clear],
              startPoint: .top,
              endPoint: .bottom
            )
            .frame(height: proxy.size.height * 0.35)
            .offset(y: sweeps ? proxy.size.height : -proxy.size.height * 0.35)
          }
          .blendMode(.plusLighter)
          .transition(.opacity)
        }
      }
      .clipShape(.rect(cornerRadius: 8, style: .continuous))
      .animation(.smooth(duration: 0.3), value: image != nil)
      .onAppear {
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) {
          sweeps = true
        }
      }
      .accessibilityHidden(true)
  }
}

private struct ReceiptRecognitionItemRow: View {
  let item: ReceiptParsePreview.Item
  let currency: String

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        Text(item.description)
        if let quantity = item.quantity, quantity != 1 {
          Text("Quantity \(quantity, format: .number)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      Group {
        if let lineTotal = item.lineTotal {
          Text(lineTotal, format: .currency(code: currency))
            .contentTransition(.numericText(value: lineTotal))
        } else {
          Text(0, format: .currency(code: currency))
            .redacted(reason: .placeholder)
        }
      }
      .font(.body.monospacedDigit())
    }
    .animation(.smooth(duration: 0.3), value: item.lineTotal)
  }
}

private struct ReceiptRecognitionPlaceholderRow: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack {
      Text("Receipt item name")
      Spacer()
      Text(0, format: .currency(code: CurrencySettings.defaultCode()))
        .monospacedDigit()
    }
    .redacted(reason: .placeholder)
    .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.45]) { content, opacity in
      content.opacity(opacity)
    } animation: { _ in
      .easeInOut(duration: 0.9)
    }
    .accessibilityHidden(true)
  }
}
