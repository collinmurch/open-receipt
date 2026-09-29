import Foundation
import Network
import Synchronization

/// Waits for a usable network path, so a read that failed offline can resume on its own.
struct ReceiptConnectivity: Sendable {
  var waitUntilConnected: @Sendable () async -> Void

  static let live = ReceiptConnectivity { await NetworkPathObserver.shared.waitUntilConnected() }
  static let immediate = ReceiptConnectivity {}
}

private final class NetworkPathObserver: Sendable {
  static let shared = NetworkPathObserver()

  private struct State {
    /// `nil` until the monitor reports its first path, which arrives shortly after it starts.
    var isConnected: Bool?
    var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
  }

  private let monitor = NWPathMonitor()
  private let state = Mutex(State())

  private init() {
    monitor.pathUpdateHandler = { [weak self] path in
      self?.update(isConnected: path.status == .satisfied)
    }
    monitor.start(queue: DispatchQueue(label: "com.collinmurch.open-receipt.network-path"))
  }

  /// Returns once the device is online, or as soon as the calling task is cancelled.
  func waitUntilConnected() async {
    let id = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let resumesNow = state.withLock { state in
          guard state.isConnected != true, !Task.isCancelled else { return true }
          state.waiters[id] = continuation
          return false
        }
        if resumesNow { continuation.resume() }
      }
    } onCancel: {
      state.withLock { $0.waiters.removeValue(forKey: id) }?.resume()
    }
  }

  private func update(isConnected: Bool) {
    let waiters = state.withLock { state in
      state.isConnected = isConnected
      guard isConnected else { return [CheckedContinuation<Void, Never>]() }
      defer { state.waiters = [:] }
      return Array(state.waiters.values)
    }
    for waiter in waiters {
      waiter.resume()
    }
  }
}
