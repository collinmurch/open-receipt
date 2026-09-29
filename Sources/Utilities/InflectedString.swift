import Foundation

extension String {
  /// A localized string with automatic grammar agreement applied, so
  /// `"^[\(count) item](inflect: true)"` reads "1 item" or "2 items".
  init(inflecting value: String.LocalizationValue) {
    self.init(AttributedString(localized: value).characters)
  }
}
