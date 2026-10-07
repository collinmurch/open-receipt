import SwiftUI

/// Marks a row that needs fixing, and lists what's wrong with it when tapped.
struct ReceiptIssuesButton: View {
  let issues: [ReceiptIssue]
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
    .accessibilityValue(issues.map(\.message).joined(separator: " "))
    .popover(isPresented: $isPresented) {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(issues) { issue in
          Text(issue.message)
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
  /// Puts a `ReceiptIssuesButton` before the view when there are issues.
  func receiptIssues(_ issues: [ReceiptIssue]) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      if !issues.isEmpty {
        ReceiptIssuesButton(issues: issues)
      }
      self
    }
  }
}
