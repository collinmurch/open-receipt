import SwiftUI

/// A trailing-aligned form text field that puts the insertion point after its text when it
/// gains focus, wherever in the row it was tapped.
struct FormTextField: View {
  let title: String
  @Binding var text: String
  @State private var selection: TextSelection?
  @FocusState private var isFocused: Bool

  init(_ title: String, text: Binding<String>) {
    self.title = title
    _text = text
  }

  var body: some View {
    TextField(title, text: $text, selection: $selection)
      .multilineTextAlignment(.trailing)
      .focused($isFocused)
      .formValueStyle(isFocused: isFocused)
      .onChange(of: isFocused) { _, focused in
        guard focused else { return }
        // UIKit places the insertion point from the tap after focus changes.
        Task { selection = TextSelection(insertionPoint: text.endIndex) }
      }
  }
}

/// A decimal form field that selects its whole value when it gains focus, so typing replaces it.
struct NumberField: View {
  let title: String
  @Binding var value: Double
  let format: FloatingPointFormatStyle<Double>
  @State private var text = ""
  @State private var selection: TextSelection?
  @FocusState private var isFocused: Bool

  init(_ title: String, value: Binding<Double>, format: FloatingPointFormatStyle<Double>) {
    self.title = title
    _value = value
    self.format = format
  }

  var body: some View {
    TextField(title, text: $text, selection: $selection)
      .keyboardType(.decimalPad)
      .monospacedDigit()
      .focused($isFocused)
      .formValueStyle(isFocused: isFocused)
      .onAppear { text = value.formatted(format) }
      .onChange(of: text) { _, newText in
        if let parsed = try? Double(newText, format: format), parsed != value {
          value = parsed
        }
      }
      .onChange(of: value) { _, newValue in
        if !isFocused { text = newValue.formatted(format) }
      }
      .onChange(of: isFocused) { _, focused in
        if focused {
          // UIKit places the insertion point from the tap after focus changes.
          Task { selection = TextSelection(range: text.startIndex..<text.endIndex) }
        } else {
          text = value.formatted(format)
        }
      }
  }
}

extension View {
  /// Shows a form value in the secondary style until its field is focused, like a Settings row.
  func formValueStyle(isFocused: Bool, isEmphasized: Bool = false) -> some View {
    foregroundStyle(isFocused || isEmphasized ? .primary : .secondary)
  }

  /// Focuses `value` when anywhere in the view is tapped, so a row's label also starts editing.
  func focusesOnTap<Value: Hashable>(
    _ focus: FocusState<Value?>.Binding,
    equals value: Value
  ) -> some View {
    contentShape(.rect).onTapGesture { focus.wrappedValue = value }
  }
}
