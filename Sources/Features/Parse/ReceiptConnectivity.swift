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
    var isConnected = true
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  private let monitor = NWPathMonitor()
  private let state = Mutex(State())

  private init() {
    monitor.pathUpdateHandler = { [weak self] path in
      self?.update(isConnected: path.status == .satisfied)
    }
    monitor.start(queue: DispatchQueue(label: "com.collinmurch.open-receipt.network-path"))
  }

  func waitUntilConnected() async {
    await withCheckedContinuation { continuation in
      let isConnected = state.withLock { state in
        if !state.isConnected { state.waiters.append(continuation) }
        return state.isConnected
      }
      if isConnected { continuation.resume() }
    }
  }

  private func update(isConnected: Bool) {
    let waiters = state.withLock { state in
      state.isConnected = isConnected
      guard isConnected else { return [CheckedContinuation<Void, Never>]() }
      defer { state.waiters = [] }
      return state.waiters
    }
    for waiter in waiters {
      waiter.resume()
    }
  }
}
