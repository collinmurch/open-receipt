import MessageUI
import SwiftUI

struct IMessageComposition: Identifiable {
  let id = UUID()
  let recipient: String
  let body: String
}

struct IMessageComposerView: UIViewControllerRepresentable {
  let composition: IMessageComposition
  let onFinish: @MainActor (Bool) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onFinish: onFinish)
  }

  func makeUIViewController(context: Context) -> MFMessageComposeViewController {
    let controller = MFMessageComposeViewController()
    controller.messageComposeDelegate = context.coordinator
    controller.recipients = [composition.recipient]
    controller.body = composition.body
    return controller
  }

  func updateUIViewController(
    _ uiViewController: MFMessageComposeViewController,
    context: Context
  ) {}

  final class Coordinator: NSObject, @preconcurrency MFMessageComposeViewControllerDelegate {
    let onFinish: @MainActor (Bool) -> Void

    init(onFinish: @escaping @MainActor (Bool) -> Void) {
      self.onFinish = onFinish
    }

    @MainActor
    func messageComposeViewController(
      _ controller: MFMessageComposeViewController,
      didFinishWith result: MessageComposeResult
    ) {
      controller.dismiss(animated: true) {
        self.onFinish(result == .sent)
      }
    }
  }
}
