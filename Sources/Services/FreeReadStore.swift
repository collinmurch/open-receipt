import Foundation
import Security

/// The record of which free reads have been used. It is kept outside the app's container, so
/// deleting and reinstalling the app doesn't reset it: in this device's keychain, in iCloud
/// Keychain, and in iCloud key-value storage. Each holds a set of read keys, and the record is
/// all of them combined.
struct FreeReadStore: Sendable {
  let load: @Sendable () -> Set<String>
  let save: @Sendable (Set<String>) -> Void
  /// Yields when another device changes the record.
  let changes: @Sendable () -> AsyncStream<Void>
}

extension FreeReadStore {
  /// Every store combined. Loading reads all of them, and saving writes the same record to each,
  /// which restores any that were cleared.
  static func merged(_ stores: [FreeReadStore]) -> FreeReadStore {
    FreeReadStore(
      load: { stores.reduce(into: Set<String>()) { $0.formUnion($1.load()) } },
      save: { reads in
        for store in stores { store.save(reads) }
      },
      changes: {
        .producing { continuation in
          await withTaskGroup(of: Void.self) { group in
            for store in stores {
              group.addTask {
                for await _ in store.changes() { continuation.yield() }
              }
            }
          }
        }
      })
  }

  static let live = FreeReadStore.merged([
    .keychain(synchronizable: false),
    .keychain(synchronizable: true),
    .iCloud,
  ])

  /// A keychain item. One that isn't synchronizable stays on this device and outlives the app;
  /// a synchronizable one also follows the Apple Account through iCloud Keychain.
  static func keychain(synchronizable: Bool) -> FreeReadStore {
    @Sendable func query() -> [CFString: Any] {
      [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "com.collinmurch.open-receipt.free-reads",
        kSecAttrAccount: "reads",
        kSecAttrSynchronizable: synchronizable,
      ]
    }
    return FreeReadStore(
      load: {
        var lookup = query()
        lookup[kSecReturnData] = true
        lookup[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data
        else { return [] }
        return decoded(data)
      },
      save: { reads in
        let data = encoded(reads)
        let update = [kSecValueData: data] as CFDictionary
        guard SecItemUpdate(query() as CFDictionary, update) == errSecItemNotFound else { return }
        var item = query()
        item[kSecValueData] = data
        item[kSecAttrAccessible] =
          synchronizable
          ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
      },
      changes: { .finished })
  }

  /// iCloud key-value storage, which follows the Apple Account even with iCloud Keychain off.
  static let iCloud = FreeReadStore(
    load: {
      let reads =
        NSUbiquitousKeyValueStore.default.array(forKey: FreeReadStore.iCloudKey) as? [String]
      return Set(reads ?? [])
    },
    save: { reads in
      NSUbiquitousKeyValueStore.default.set(reads.sorted(), forKey: FreeReadStore.iCloudKey)
    },
    changes: {
      .producing { continuation in
        NSUbiquitousKeyValueStore.default.synchronize()
        let notifications = NotificationCenter.default.notifications(
          named: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
        for await _ in notifications {
          continuation.yield()
        }
      }
    })

  private static let iCloudKey = "freeReads"

  /// Keeps reads in memory, for tests and screenshots.
  static func memory(_ initial: Set<String> = []) -> FreeReadStore {
    let reads = Locked(initial)
    return FreeReadStore(
      load: { reads.value },
      save: { reads.value = $0 },
      changes: { .finished })
  }

  private static func encoded(_ reads: Set<String>) -> Data {
    (try? JSONEncoder().encode(reads.sorted())) ?? Data()
  }

  private static func decoded(_ data: Data) -> Set<String> {
    Set((try? JSONDecoder().decode([String].self, from: data)) ?? [])
  }
}
