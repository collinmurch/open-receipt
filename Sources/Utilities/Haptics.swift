import SwiftUI

extension SensoryFeedback {
  /// Played after a person removes content, such as a receipt, item, page, or person.
  static let removal = SensoryFeedback.impact(weight: .medium)
}

/// A haptic requested by an action. Every `play` produces a new value, so the same feedback
/// plays again on repeated actions.
struct HapticEvent: Equatable {
  private(set) var feedback: SensoryFeedback?
  private var count = 0

  mutating func play(_ feedback: SensoryFeedback) {
    self.feedback = feedback
    count += 1
  }
}

extension View {
  /// Plays each feedback requested through `event`. Attach it to a view that outlives the action,
  /// not to a list section or a screen the action dismisses.
  func haptics(_ event: HapticEvent) -> some View {
    sensoryFeedback(trigger: event) { _, newEvent in newEvent.feedback }
  }

  /// Plays error feedback when `errorDescription` appears, alongside the alert that shows it.
  func errorHaptic(_ errorDescription: String?) -> some View {
    sensoryFeedback(.error, trigger: errorDescription) { oldValue, newValue in
      oldValue == nil && newValue != nil
    }
  }
}
