import SwiftUI

/// A menu of the contact's phone numbers and email addresses, plus a custom entry that selects
/// `nil`.
struct ContactRecipientPicker<Recipient: ContactRecipient>: View {
  private struct Option: Identifiable {
    let recipient: Recipient
    let title: String

    var id: Recipient.ID { recipient.id }
  }

  let contact: ContactSummary?
  @Binding var selection: Recipient?
  let customTitle: LocalizedStringKey

  var body: some View {
    let options = self.options
    LabeledContent("Recipient") {
      Menu {
        ForEach(options) { option in
          Toggle(isOn: isSelected(option.recipient)) {
            Text(option.title)
          }
        }
        Toggle(isOn: isSelected(nil)) {
          Text(customTitle)
        }
      } label: {
        if let option = options.first(where: { $0.recipient == selection }) {
          Text(option.title)
        } else {
          Text(customTitle)
        }
      }
    }
  }

  private var options: [Option] {
    let phoneNumbers = (contact?.phoneNumbers ?? []).map {
      (recipient: Recipient.phoneNumber($0.value), label: $0.label)
    }
    let emailAddresses = (contact?.emailAddresses ?? []).map {
      (recipient: Recipient.emailAddress($0.value), label: $0.label)
    }
    var options: [Option] = []
    for (recipient, label) in phoneNumbers + emailAddresses {
      guard !options.contains(where: { $0.recipient == recipient }) else { continue }
      let title = label.map { "\($0): \(recipient.displayValue)" } ?? recipient.displayValue
      options.append(Option(recipient: recipient, title: title))
    }
    if let selection, !options.contains(where: { $0.recipient == selection }) {
      options.append(Option(recipient: selection, title: selection.displayValue))
    }
    return options
  }

  private func isSelected(_ recipient: Recipient?) -> Binding<Bool> {
    Binding(
      get: { selection == recipient },
      set: { isSelected in
        if isSelected {
          selection = recipient
        }
      })
  }
}
