extension Optional {
  /// Whether a value is set. Setting false clears it, so `$value.isPresent` can drive a
  /// presentation that dismisses by clearing the value.
  var isPresent: Bool {
    get { self != nil }
    set { if !newValue { self = nil } }
  }
}
