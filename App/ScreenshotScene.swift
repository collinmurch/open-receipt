#if DEBUG
  import SwiftUI

  /// A receipt photo and the values it reads as, who had what, and the rest of the library.
  struct ScreenshotScene: Decodable {
    struct Item: Decodable {
      let description: String
      var quantity: Double?
      let lineTotal: Double
    }

    /// Who is on a scenario's receipt and which items each of them had. Names match `people`, and
    /// the person using the app is `owner`, or "Me" without one.
    struct Group: Decodable {
      var owner: String?
      let assignments: [String: [String]]
    }

    /// Someone on the receipt, with the payment method they are requested through and the phone
    /// number on their contact card.
    struct Participant: Decodable {
      let name: String
      var venmo: String?
      var cashApp: String?
      var iMessage: String?
      var phone: String?

      /// The identifier of the contact card the share scenario picks them from, if they have one.
      var contactIdentifier: String? {
        phone == nil ? nil : "screenshot-\(name)"
      }

      var paymentMethods: Person.PaymentMethods {
        let defaultMethod: PaymentMethod? =
          if venmo != nil { .venmo } else if cashApp != nil { .cashApp } else if iMessage != nil {
            .iMessage
          } else { nil }
        return Person.PaymentMethods(
          defaultMethod: defaultMethod,
          venmo: venmo.map(Person.Venmo.init(username:)),
          cashApp: cashApp.map { Person.CashApp(cashtag: $0) },
          iMessage: iMessage.map {
            Person.IMessage(recipient: .init(kind: .phoneNumber, value: $0))
          })
      }
    }

    /// Another receipt in the library, dated relative to the capture.
    struct LibraryEntry: Decodable {
      let merchant: String
      let daysAgo: Int
      let total: Double
      let backgroundStyle: ReceiptBackgroundStyle

      func receipt(date: String) -> ParsedReceipt {
        ParsedReceipt(
          merchantName: merchant,
          date: date,
          subtotal: total,
          total: total,
          items: [ReceiptItem(description: merchant, quantity: 1, lineTotal: total)])
      }
    }

    let id: UUID
    let image: String
    let merchant: String
    let date: String
    let currency: String
    let subtotal: Double
    let tax: Double
    let total: Double
    /// A tip entered after the receipt is read.
    var addedTip: Double?
    let backgroundStyle: ReceiptBackgroundStyle
    let people: [Participant]
    let items: [Item]
    /// People and assignments for each scenario that splits the receipt, keyed by scenario.
    let groups: [String: Group]
    var library: [LibraryEntry]?
    private(set) var imageURL = URL(filePath: "/")

    private enum CodingKeys: String, CodingKey {
      case id, image, merchant, date, currency, subtotal, tax, total, addedTip, backgroundStyle,
        people, items, groups, library
    }

    static func load(from url: URL) throws -> ScreenshotScene {
      var scene = try JSONDecoder().decode(ScreenshotScene.self, from: Data(contentsOf: url))
      scene.imageURL = url.deletingLastPathComponent().appending(path: scene.image)
      return scene
    }

    var receipt: ParsedReceipt {
      ParsedReceipt(
        merchantName: merchant,
        date: date,
        subtotal: subtotal,
        tax: tax,
        total: total,
        currency: currency,
        items: items.map {
          ReceiptItem(
            description: $0.description, quantity: $0.quantity ?? 1, lineTotal: $0.lineTotal)
        })
    }
  }

  enum ScreenshotSceneError: Error {
    case unreadableImage(URL)
    case unreadReceipt
    case missingGroup(String)
  }
#endif
