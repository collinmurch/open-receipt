import SwiftUI

extension View {
  /// Shows buttons above the keyboard that move to the previous or next of `fields`, listed in the
  /// order they appear, and one that closes the keyboard. Return in a text field moves to the next
  /// field too.
  ///
  /// With `proxy`, a field is scrolled to before it's focused, since a list only builds the rows
  /// near the screen and a field in a row it hasn't built can't take focus. That takes the field's
  /// row having the field as its `id`; rows next to each other don't need one.
  func keyboardNavigation<Field: Hashable & Sendable>(
    _ focus: FocusState<Field?>.Binding,
    through fields: [Field],
    scrollingWith proxy: ScrollViewProxy? = nil
  ) -> some View {
    let navigation = KeyboardNavigation(focus: focus, fields: fields, proxy: proxy)
    return
      self
      .onSubmit { navigation.next?() }
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Button("Previous Field", systemImage: "chevron.up") { navigation.previous?() }
            .disabled(navigation.previous == nil)
          Button("Next Field", systemImage: "chevron.down") { navigation.next?() }
            .disabled(navigation.next == nil)
          Spacer()
          Button("Done", systemImage: "checkmark") { focus.wrappedValue = nil }
        }
      }
  }
}

private struct KeyboardNavigation<Field: Hashable & Sendable> {
  let focus: FocusState<Field?>.Binding
  let fields: [Field]
  let proxy: ScrollViewProxy?

  var previous: (@MainActor () -> Void)? {
    move(by: -1)
  }

  var next: (@MainActor () -> Void)? {
    move(by: 1)
  }

  private func move(by offset: Int) -> (@MainActor () -> Void)? {
    guard let focused = focus.wrappedValue, let index = fields.firstIndex(of: focused),
      fields.indices.contains(index + offset)
    else { return nil }
    let field = fields[index + offset]
    return {
      guard let proxy else {
        focus.wrappedValue = field
        return
      }
      proxy.scrollTo(field)
      // The row the list just scrolled to is built on its next update.
      Task { focus.wrappedValue = field }
    }
  }
}
