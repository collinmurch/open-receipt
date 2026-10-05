extension AsyncStream {
  /// A stream that ends without yielding anything.
  static var finished: AsyncStream {
    AsyncStream { $0.finish() }
  }
}
