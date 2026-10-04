import Foundation

enum ReceiptCurrency {
  /// `code` when it is a currency code, or `fallback` otherwise.
  static func displayCode(
    _ code: String?,
    fallback: @autoclosure () -> String = CurrencySettings.defaultCode()
  ) -> String {
    guard let code, ReceiptValidator.isCurrencyCode(code) else { return fallback() }
    return code
  }

  /// The localized name of `code`, such as "US Dollar" for USD.
  static func localizedName(_ code: String) -> String {
    Locale.current.localizedString(forCurrencyCode: code) ?? code
  }

  /// The signs written for `code`, both in the current locale and where the currency is used,
  /// such as "$" and "US$" for USD or "PLN" and "zł" for PLN.
  static func symbols(_ code: String) -> [String] {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = code
    var symbols = [formatter.currencySymbol ?? code]
    if let locale = nativeLocalesByCode[code] {
      formatter.locale = locale
      formatter.currencyCode = code
      if let native = formatter.currencySymbol, !symbols.contains(native) {
        symbols.append(native)
      }
    }
    return symbols
  }

  private static let nativeLocalesByCode: [String: Locale] = {
    let regional = Locale.availableIdentifiers.sorted().map(Locale.init(identifier:))
      .filter { $0.region != nil }
    // Prefer each region's primary language, so PLN reads from pl_PL rather than en_PL.
    let primary = regional.filter(isPrimaryLanguageLocale)
    var locales: [String: Locale] = [:]
    for locale in primary + regional {
      guard let code = locale.currency?.identifier, locales[code] == nil else { continue }
      locales[code] = locale
    }
    return locales
  }()

  private static func isPrimaryLanguageLocale(_ locale: Locale) -> Bool {
    guard let region = locale.region, let language = locale.language.languageCode else {
      return false
    }
    let likely = Locale.Language(identifier: "und-\(region.identifier)").maximalIdentifier
    return Locale.Language(identifier: likely).languageCode == language
  }

  /// The SF Symbol for `code`'s currency sign, or a banknote when there is none.
  static func symbolName(_ code: String) -> String {
    symbolNamesByCode[code.uppercased()] ?? "banknote"
  }

  private static let symbolNamesByCode: [String: String] = [
    "ARS": "dollarsign", "AUD": "australiandollarsign", "AWG": "florinsign",
    "AZN": "manatsign", "BRL": "brazilianrealsign", "CAD": "dollarsign", "CHF": "francsign",
    "CLP": "dollarsign", "CNY": "chineseyuanrenminbisign", "COP": "dollarsign",
    "CRC": "coloncurrencysign", "DKK": "danishkronesign", "EUR": "eurosign",
    "GBP": "sterlingsign", "GEL": "larisign", "GHS": "cedisign", "HKD": "dollarsign",
    "ILS": "shekelsign", "INR": "indianrupeesign", "JPY": "yensign", "KRW": "wonsign",
    "KZT": "tengesign", "LAK": "kipsign", "LKR": "rupeesign", "MNT": "tugriksign",
    "MXN": "dollarsign", "MYR": "malaysianringgitsign", "NGN": "nairasign",
    "NOK": "norwegiankronesign", "NPR": "rupeesign", "NZD": "dollarsign",
    "PEN": "peruviansolessign", "PHP": "pesosign", "PKR": "rupeesign", "PLN": "polishzlotysign",
    "PYG": "guaranisign", "RUB": "rublesign", "SEK": "swedishkronasign",
    "SGD": "singaporedollarsign", "THB": "bahtsign", "TRY": "turkishlirasign",
    "TWD": "dollarsign", "UAH": "hryvniasign", "USD": "dollarsign", "UYU": "dollarsign",
    "VND": "dongsign",
  ]
}
