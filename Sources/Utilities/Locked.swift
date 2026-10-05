import Synchronization

/// A value that closures on any thread can read and replace, such as the state behind an
/// in-memory client.
final class Locked<Value: Sendable>: Sendable {
  private let mutex: Mutex<Value>

  init(_ value: Value) {
    mutex = Mutex(value)
  }

  var value: Value {
    get { mutex.withLock { $0 } }
    set { mutex.withLock { $0 = newValue } }
  }
}
