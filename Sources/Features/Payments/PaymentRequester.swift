import MessageUI
import SwiftUI

/// Opens payment requests, composing iMessage requests with the person's breakdown attached, and
/// messages breakdowns. Present what it needs with `paymentRequestPresentation(_:)`.
@MainActor
@Observable
final class PaymentRequester {
  var composition: IMessageComposition?
  var errorDescription: String?
  @ObservationIgnored private var onComposedRequestSent: (() -> Void)?
  @ObservationIgnored private var isPreparingComposition = false

  func open(
    _ request: PreparedPaymentRequest,
    breakdown: ReceiptBreakdown?,
    openURL: OpenURLAction,
    onSent: @escaping () -> Void
  ) {
    switch request.action {
    case .openURL(let url):
      openURL(url) { accepted in
        if accepted {
          onSent()
        } else {
          self.errorDescription =
            request.method == .venmo
            ? "Install Venmo to open this payment request."
            : "Cash App could not open this payment link."
        }
      }
    case .compose(let recipient, let body):
      guard MFMessageComposeViewController.canSendText() else {
        errorDescription = "iMessage is not available on this device."
        return
      }
      compose(
        recipients: [recipient], body: body, breakdowns: breakdown.map { [$0] } ?? [],
        onSent: onSent)
    }
  }

  /// Composes a message to `recipients`, which is a group chat when there are several, with
  /// `breakdowns` attached in order. The first breakdown's text introduces them.
  func message(
    _ breakdowns: [ReceiptBreakdown],
    to recipients: [Person.IMessage.Recipient],
    onSent: @escaping () -> Void
  ) {
    guard let first = breakdowns.first, !recipients.isEmpty else { return }
    guard MFMessageComposeViewController.canSendText() else {
      errorDescription = "iMessage is not available on this device."
      return
    }
    compose(
      recipients: recipients.map(\.value), body: first.messageBody, breakdowns: breakdowns,
      onSent: onSent)
  }

  /// Ignores taps while a composer is already being prepared or shown.
  private func compose(
    recipients: [String],
    body: String,
    breakdowns: [ReceiptBreakdown],
    onSent: @escaping () -> Void
  ) {
    guard !isPreparingComposition, composition == nil else { return }
    onComposedRequestSent = onSent
    isPreparingComposition = true
    Task {
      let attachments = await attachments(for: breakdowns)
      composition = IMessageComposition(
        recipients: recipients, body: body, attachments: attachments)
      isPreparingComposition = false
    }
  }

  private func attachments(for breakdowns: [ReceiptBreakdown]) async -> [IMessageAttachment] {
    guard MFMessageComposeViewController.canSendAttachments() else { return [] }
    // Every card is drawn up front so their encodes run side by side.
    for breakdown in breakdowns { ReceiptBreakdownRenderer.image(for: breakdown) }
    var attachments: [IMessageAttachment] = []
    for breakdown in breakdowns {
      if let attachment = await IMessageAttachment(breakdown: breakdown) {
        attachments.append(attachment)
      }
    }
    return attachments
  }

  fileprivate func finishComposing(sent: Bool) {
    composition = nil
    if sent { onComposedRequestSent?() }
    onComposedRequestSent = nil
  }
}

extension IMessageAttachment {
  @MainActor
  fileprivate init?(breakdown: ReceiptBreakdown) async {
    guard let data = await ReceiptBreakdownRenderer.pngData(for: breakdown) else { return nil }
    self.init(data: data, filename: "\(breakdown.fileName).png")
  }
}

extension View {
  /// Presents the message composer and errors for requests opened by `requester`.
  func paymentRequestPresentation(_ requester: PaymentRequester) -> some View {
    modifier(PaymentRequestPresentation(requester: requester))
  }
}

private struct PaymentRequestPresentation: ViewModifier {
  @Bindable var requester: PaymentRequester

  func body(content: Content) -> some View {
    content
      .sheet(item: $requester.composition) { composition in
        IMessageComposerView(composition: composition) { sent in
          requester.finishComposing(sent: sent)
        }
      }
      .errorAlert("Couldn’t Open Payment Request", message: $requester.errorDescription)
  }
}
