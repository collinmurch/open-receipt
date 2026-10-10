import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// A finished split as it is shared: one person's share, or everyone's. It copies what it shows
/// out of the receipt, so it renders the same however the receipt changes afterward.
struct ReceiptBreakdown: Equatable, Sendable {
  enum Content: Equatable, Sendable {
    case person(ReceiptParticipantShare)
    case group([ReceiptParticipantShare])
  }

  let merchantName: String
  let purchaseDate: Date
  let currency: String
  let adjustmentMethod: ReceiptAdjustmentSplitMethod
  let style: ReceiptBackgroundStyle
  /// The appearance the sender sees the receipt in, so the card's accent matches their tint.
  let accentScheme: ColorScheme
  let content: Content
  /// The contact photos of the people it shows, captured because the card is drawn at once.
  var photos: [ReceiptParticipant.ID: Data] = [:]

  var merchantTitle: String {
    let merchant = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    return merchant.isEmpty ? "Receipt" : merchant
  }

  var title: String {
    switch content {
    case .person(let share):
      "\(merchantTitle) – \(share.participant.displayName)"
    case .group:
      merchantTitle
    }
  }

  /// `title` without characters a file name can't hold.
  var fileName: String {
    title.replacing(/[\/:\\]/, with: "-")
  }

  /// The text sent with the breakdown when it is messaged.
  var messageBody: String {
    let amount = total.formatted(.currency(code: currency))
    switch content {
    case .person:
      return "Here’s your share of \(merchantTitle): \(amount)."
    case .group:
      return "Here’s how we split \(merchantTitle): \(amount) total."
    }
  }

  var total: Double {
    shares.reduce(0) { $0 + $1.total }
  }

  var shares: [ReceiptParticipantShare] {
    switch content {
    case .person(let share): [share]
    case .group(let shares): shares
    }
  }
}

extension ReceiptDraft {
  /// The breakdown of one person's share, once every item is assigned.
  func breakdown(
    for share: ReceiptParticipantShare,
    accentScheme: ColorScheme,
    photos: ContactPhotos? = nil
  ) -> ReceiptBreakdown? {
    breakdown(.person(share), accentScheme: accentScheme, photos: photos)
  }

  /// The breakdown of everyone's shares, once every item is assigned.
  func groupBreakdown(
    accentScheme: ColorScheme,
    photos: ContactPhotos? = nil
  ) -> ReceiptBreakdown? {
    breakdown(
      .group(splitCalculation.participantShares), accentScheme: accentScheme, photos: photos)
  }

  /// The overview followed by each person's breakdown, once every item is assigned.
  func allBreakdowns(
    accentScheme: ColorScheme,
    photos: ContactPhotos? = nil
  ) -> [ReceiptBreakdown]? {
    guard let overview = groupBreakdown(accentScheme: accentScheme, photos: photos) else {
      return nil
    }
    let people = splitCalculation.participantShares.compactMap {
      breakdown(for: $0, accentScheme: accentScheme, photos: photos)
    }
    return [overview] + people
  }

  private func breakdown(
    _ content: ReceiptBreakdown.Content,
    accentScheme: ColorScheme,
    photos: ContactPhotos?
  ) -> ReceiptBreakdown? {
    guard splitCalculation.unassignedItemCount == 0 else { return nil }
    var breakdown = ReceiptBreakdown(
      merchantName: merchantName,
      purchaseDate: purchaseDate,
      currency: displayCurrency,
      adjustmentMethod: adjustmentSplitMethod,
      style: backgroundStyle,
      accentScheme: accentScheme,
      content: content)
    if let photos {
      for share in breakdown.shares {
        breakdown.photos[share.id] = photos[share.participant.source.contactIdentifier]
      }
    }
    return breakdown
  }
}

extension ReceiptBreakdown: Transferable {
  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .png) { breakdown in
      try await ReceiptBreakdownRenderer.pngData(for: breakdown).orThrow()
    }
    .suggestedFileName { $0.fileName }
    DataRepresentation(exportedContentType: .pdf) { breakdown in
      try await MainActor.run { try ReceiptBreakdownRenderer.pdfData(for: breakdown).orThrow() }
    }
    .suggestedFileName { $0.fileName }
  }
}

private struct ReceiptBreakdownRenderingError: Error {}

extension Data? {
  fileprivate func orThrow() throws -> Data {
    guard let self else { throw ReceiptBreakdownRenderingError() }
    return self
  }
}
