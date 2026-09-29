import SwiftUI

/// A person or contact in a list the user picks from, checked when selected.
struct PersonSelectionRow: View {
  let name: String
  let avatarData: Data?
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 12) {
      PersonAvatarView(name: name, imageData: avatarData)
      Text(name)
        .foregroundStyle(.primary)
      Spacer()
      if isSelected {
        Image(systemName: "checkmark")
          .fontWeight(.semibold)
          .foregroundStyle(.tint)
      }
    }
    .contentShape(.rect)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
