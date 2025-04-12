import Foundation

public struct URLRequestConvertibleWrapper: URLRequestConvertible {
  public let request: URLRequest

  public init(_ request: URLRequest) {
    self.request = request
  }

  public func asURLRequest() throws -> URLRequest {
    request
  }
}
