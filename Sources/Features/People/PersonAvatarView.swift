import SwiftUI

struct PersonAvatarView: View {
  let name: String
  let imageData: Data?
  var size: CGFloat = 36

  var body: some View {
    Group {
      if let image = imageData.flatMap(PersonAvatarImageCache.image) {
        // Buttons in lists draw images as templates in their tint unless told otherwise.
        Image(uiImage: image)
          .renderingMode(.original)
          .resizable()
          .scaledToFill()
      } else {
        Text(initials)
          .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.secondary.opacity(0.18))
      }
    }
    .frame(width: size, height: size)
    .clipShape(.circle)
    .accessibilityHidden(true)
  }

  private var initials: String {
    let words = name.split(whereSeparator: \.isWhitespace)
    let characters = words.prefix(2).compactMap(\.first)
    return characters.isEmpty ? "?" : String(characters).uppercased()
  }
}

@MainActor
private enum PersonAvatarImageCache {
  private static let cache: NSCache<NSData, UIImage> = {
    let cache = NSCache<NSData, UIImage>()
    cache.countLimit = 100
    return cache
  }()

  static func image(for data: Data) -> UIImage? {
    let key = data as NSData
    if let image = cache.object(forKey: key) {
      return image
    }
    guard let image = UIImage(data: data) else { return nil }
    cache.setObject(image, forKey: key, cost: data.count)
    return image
  }
}
