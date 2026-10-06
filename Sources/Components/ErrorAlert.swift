import SwiftUI

extension View {
  /// Shows `message` in an alert while it is set and plays error feedback when it appears.
  /// Dismissing the alert clears `message`.
  func errorAlert<Actions: View>(
    _ title: LocalizedStringKey,
    message: Binding<String?>,
    @ViewBuilder actions: @escaping () -> Actions
  ) -> some View {
    alert(
      title,
      isPresented: message.isPresent,
      presenting: message.wrappedValue,
      actions: { _ in actions() },
      message: { Text($0) }
    )
    .sensoryFeedback(.error, trigger: message.wrappedValue) { oldValue, newValue in
      oldValue == nil && newValue != nil
    }
  }

  /// Shows `message` in an alert with an OK button while it is set.
  func errorAlert(_ title: LocalizedStringKey, message: Binding<String?>) -> some View {
    errorAlert(title, message: message) {
      Button("OK", role: .cancel) {}
    }
  }
}
