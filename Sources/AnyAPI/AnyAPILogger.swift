import Foundation

public struct AnyAPILogger {
  public var onRequest: ((URLRequest) -> Void)?
  public var onResponse: ((AFDataResponse<Data>) -> Void)?

  public init() {}
}
