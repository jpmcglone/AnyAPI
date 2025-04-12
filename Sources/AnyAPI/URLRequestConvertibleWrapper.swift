import Foundation

struct URLRequestConvertibleWrapper: URLRequestConvertible {
  let request: URLRequest
  init(_ request: URLRequest) {
    self.request = request
  }

  func asURLRequest() throws -> URLRequest {
    request
  }
}
