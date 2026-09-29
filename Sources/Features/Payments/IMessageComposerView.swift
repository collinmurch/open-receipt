import MessageUI
import SwiftUI
import UniformTypeIdentifiers

struct IMessageComposition: Identifiable {
  let id = UUID()
  let recipients: [String]
  let body: String
  var attachments: [IMessageAttachment] = []
}

/// An image sent along with a message.
struct IMessageAttachment {
  let data: Data
  let filename: String
}

extension IMessageAttachment {
  @MainActor
  init?(breakdown: ReceiptBreakdown) {
    guard let data = ReceiptBreakdownRenderer.pngData(for: breakdown) else { return nil }
    self.init(data: data, filename: "\(breakdown.fileName).png")
  }
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
    controller.recipients = composition.recipients
    controller.body = composition.body
    for attachment in composition.attachments {
      controller.addAttachmentData(
        attachment.data, typeIdentifier: UTType.png.identifier, filename: attachment.filename)
    }
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
