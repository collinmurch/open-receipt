import SwiftUI

/// Marks a row that needs fixing, and lists what's wrong with it when tapped.
struct IssuesButton: View {
  let messages: [String]
  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented = true
    } label: {
      Image(systemName: "exclamationmark.circle.fill")
        .foregroundStyle(.orange)
        .contentShape(.rect)
    }
    .buttonStyle(.borderless)
    .accessibilityLabel("Needs fixing")
    .accessibilityValue(messages.joined(separator: " "))
    .popover(isPresented: $isPresented) {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(messages, id: \.self) { message in
          Text(message)
        }
      }
      .font(.subheadline)
      .fixedSize(horizontal: false, vertical: true)
      .padding()
      .presentationCompactAdaptation(.popover)
    }
  }
}

extension View {
  /// Puts an `IssuesButton` before the view when there are issues.
  func issues(_ messages: [String]) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      if !messages.isEmpty {
        IssuesButton(messages: messages)
      }
      self
    }
  }

  /// Puts an `IssuesButton` listing a receipt's `issues` before the view when there are any.
  func receiptIssues(_ issues: [ReceiptIssue]) -> some View {
    self.issues(issues.map(\.message))
  }
}
