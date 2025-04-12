import Alamofire

public extension HTTPHeaders {
  /// Returns a new `HTTPHeaders` instance by merging the current headers with the provided ones.
  /// In case of duplicate header names, the values from the provided headers will overwrite the existing ones.
  func merging(_ other: HTTPHeaders) -> HTTPHeaders {
    var merged = self
    for header in other {
      merged.update(name: header.name, value: header.value)
    }
    return merged
  }

  /// Merges the provided headers into the current `HTTPHeaders` instance.
  /// In case of duplicate header names, the values from the provided headers will overwrite the existing ones.
  mutating func merge(_ other: HTTPHeaders) {
    for header in other {
      self.update(name: header.name, value: header.value)
    }
  }
}
