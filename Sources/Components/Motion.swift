import SwiftUI

extension Animation {
  /// A row lifting out of its list into focus.
  static let lift = Animation.spring(duration: 0.35, bounce: 0.2)

  /// A focused row returning to its list, and other changes of focus or editing.
  static let settle = Animation.smooth(duration: 0.35)

  /// A quick change of selection, such as choosing people or items.
  static let selectionChange = Animation.smooth(duration: 0.25)

  /// Glass controls morphing into one another.
  static let glassMorph = Animation.bouncy(duration: 0.5, extraBounce: 0.1)
}
