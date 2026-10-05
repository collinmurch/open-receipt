extension AsyncStream {
  /// A stream that ends without yielding anything.
  static var finished: AsyncStream {
    AsyncStream { $0.finish() }
  }

  /// A stream fed by `produce`, which finishes when `produce` returns and stops it when the
  /// stream ends first.
  static func producing(
    _ produce: @escaping @Sendable (Continuation) async -> Void
  ) -> AsyncStream {
    AsyncStream { continuation in
      let task = Task {
        await produce(continuation)
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
