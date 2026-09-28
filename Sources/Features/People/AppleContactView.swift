import Contacts
import ContactsUI
import SwiftUI

struct AppleContactView: UIViewControllerRepresentable {
  let identifier: String
  let onClose: @MainActor () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onClose: onClose)
  }

  func makeUIViewController(context: Context) -> UINavigationController {
    let rootViewController: UIViewController
    do {
      let contact = try context.coordinator.store.unifiedContact(
        withIdentifier: identifier,
        keysToFetch: [CNContactViewController.descriptorForRequiredKeys()])
      let contactViewController = CNContactViewController(for: contact)
      contactViewController.contactStore = context.coordinator.store
      contactViewController.allowsActions = true
      contactViewController.allowsEditing = true
      contactViewController.shouldShowLinkedContacts = true
      rootViewController = contactViewController
    } catch {
      rootViewController = UIHostingController(
        rootView: ContentUnavailableView(
          "Contact Not Available",
          systemImage: "person.crop.circle.badge.exclamationmark"))
    }
    rootViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .close,
      target: context.coordinator,
      action: #selector(Coordinator.close))
    return UINavigationController(rootViewController: rootViewController)
  }

  func updateUIViewController(
    _ uiViewController: UINavigationController,
    context: Context
  ) {}

  @MainActor
  final class Coordinator: NSObject {
    let store = CNContactStore()
    let onClose: @MainActor () -> Void

    init(onClose: @escaping @MainActor () -> Void) {
      self.onClose = onClose
    }

    @objc func close() {
      onClose()
    }
  }
}
