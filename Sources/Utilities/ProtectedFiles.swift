import Foundation

extension FileManager {
  /// `name` within the app's folder in Application Support.
  func openReceiptDirectory(_ name: String) throws -> URL {
    try url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    )
    .appending(path: "OpenReceipt", directoryHint: .isDirectory)
    .appending(path: name, directoryHint: .isDirectory)
  }

  /// Creates a directory and any missing parents, readable once the device is first unlocked.
  func createProtectedDirectory(at url: URL) throws {
    try createDirectory(
      at: url,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
  }

  /// Makes the item at `url` readable once the device is first unlocked.
  func protectItem(at url: URL) throws {
    try setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path)
  }
}
