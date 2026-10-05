import SwiftUI

/// A list row with a centered, labeled spinner.
struct LoadingRow: View {
  let title: LocalizedStringKey

  var body: some View {
    HStack {
      Spacer()
      ProgressView(title)
      Spacer()
    }
  }
}
