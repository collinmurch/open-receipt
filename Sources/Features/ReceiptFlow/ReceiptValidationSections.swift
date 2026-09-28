import SwiftUI

struct ReceiptWarningsSection: View {
  let warnings: [String]

  var body: some View {
    if !warnings.isEmpty {
      Section("Validation") {
        ForEach(warnings, id: \.self) { warning in
          Label(warning, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        }
      }
    }
  }
}

struct ReceiptEditorValidationSection: View {
  let issues: [ReceiptEditorValidationIssue]

  var body: some View {
    let messages = Array(Set(issues.map(\.message))).sorted()
    if !messages.isEmpty {
      Section("Check These Fields") {
        ForEach(messages, id: \.self) { message in
          Label(message, systemImage: "exclamationmark.circle")
            .foregroundStyle(.red)
        }
      }
    }
  }
}
