import Foundation
import Alamofire

public struct AnyAPILogger {
  public var onRequest: ((URLRequest) -> Void)?
  public var onResponse: ((AFDataResponse<Data>) -> Void)?

  public init(
    onRequest: ((URLRequest) -> Void)? = nil,
    onResponse: ((AFDataResponse<Data>) -> Void)? = nil
  ) {
    self.onRequest = onRequest
    self.onResponse = onResponse
  }
}
