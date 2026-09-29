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
      onComposedRequestSent = onSent
      composition = IMessageComposition(
        recipients: [recipient], body: body,
        attachments: attachments(for: breakdown.map { [$0] } ?? []))
    }
  }

  /// Composes a message to `recipients`, which is a group chat when there are several, with
  /// `breakdowns` attached in order. The first breakdown's text introduces them.
  func message(_ breakdowns: [ReceiptBreakdown], to recipients: [Person.IMessage.Recipient]) {
    guard let first = breakdowns.first, !recipients.isEmpty else { return }
    guard MFMessageComposeViewController.canSendText() else {
      errorDescription = "iMessage is not available on this device."
      return
    }
    onComposedRequestSent = nil
    composition = IMessageComposition(
      recipients: recipients.map(\.value),
      body: first.messageBody,
      attachments: attachments(for: breakdowns))
  }

  private func attachments(for breakdowns: [ReceiptBreakdown]) -> [IMessageAttachment] {
    guard MFMessageComposeViewController.canSendAttachments() else { return [] }
    return breakdowns.compactMap(IMessageAttachment.init(breakdown:))
  }

  fileprivate func finishComposing(sent: Bool) {
    composition = nil
    if sent { onComposedRequestSent?() }
    onComposedRequestSent = nil
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
