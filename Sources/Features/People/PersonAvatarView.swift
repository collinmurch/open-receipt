import SwiftUI

struct PersonAvatarView: View {
  let name: String
  let imageData: Data?
  /// A fixed diameter, or `nil` for one that grows with Dynamic Type from a list row's size.
  var size: CGFloat?
  @ScaledMetric(relativeTo: .body) private var scaledSize = 36

  var body: some View {
    let size = self.size ?? scaledSize

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

/// A person's avatar showing the photo on their contact card, when they have one.
struct ContactAvatarView: View {
  let name: String
  let contactIdentifier: String?
  var size: CGFloat?
  @Environment(ContactPhotos.self) private var photos: ContactPhotos?

  var body: some View {
    PersonAvatarView(name: name, imageData: photos?[contactIdentifier], size: size)
      .task(id: contactIdentifier) { await photos?.load(contactIdentifier) }
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
