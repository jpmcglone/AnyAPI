import Alamofire
import Foundation

public struct RequestOptions {
  public var additionalParameters: Parameters = [:]
  public var additionalHeaders: HTTPHeaders = [:]
  public var overrideParameters: Parameters? = nil
  public var overrideHeaders: HTTPHeaders? = nil
  public var encoding: ParameterEncoding? = nil
  public var onRequest: ((URLRequest) -> Void)? = nil
  public var onResponse: ((AFDataResponse<Data>) -> Void)? = nil
  public var decoder: ((Data) throws -> Any)? = nil

  public var mock: MockResponse? = nil
  public var retryPolicy: RetryPolicy? = nil
  public var authFailureHandler: ((APIClient) async -> Void)? = nil
  public var multipartFormDataBuilder: ((MultipartFormData) -> Void)? = nil
  public var timeoutInterval: TimeInterval? = nil
  public var interceptor: ((inout URLRequest) -> Void)? = nil

  public var responseInterceptor: ((Data, HTTPURLResponse) throws -> Data)? = nil
  public var onErrorHandler: ((Error) -> Void)? = nil
  public var onProgress: (@Sendable (Progress) -> Void)? = nil
  public var requestDelay: TimeInterval? = nil // 👈 Add this

  public init() {}

  public func additionalParameters(_ new: Parameters) -> Self {
    var copy = self
    copy.additionalParameters.merge(new) { _, new in new }
    return copy
  }

  public func additionalHeaders(_ new: HTTPHeaders) -> Self {
    var copy = self
    copy.additionalHeaders.merge(new)
    return copy
  }

  public func overrideParameters(_ new: Parameters) -> Self {
    var copy = self
    copy.overrideParameters = new
    return copy
  }

  public func overrideHeaders(_ new: HTTPHeaders) -> Self {
    var copy = self
    copy.overrideHeaders = new
    return copy
  }

  public func encoding(_ new: ParameterEncoding) -> Self {
    var copy = self
    copy.encoding = new
    return copy
  }

  public func onRequest(_ callback: @escaping (URLRequest) -> Void) -> Self {
    var copy = self
    copy.onRequest = callback
    return copy
  }

  public func onResponse(_ callback: @escaping (AFDataResponse<Data>) -> Void) -> Self {
    var copy = self
    copy.onResponse = callback
    return copy
  }

  public func decodeWith(_ block: @escaping (Data) throws -> Any) -> Self {
    var copy = self
    copy.decoder = block
    return copy
  }

  public func decodeAs<T: Decodable>(_ type: T.Type) -> Self {
    decodeWith { data in
      try JSONDecoder().decode(T.self, from: data)
    }
  }

  public func decodeAs<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder) -> Self {
    decodeWith { data in
      try decoder.decode(T.self, from: data)
    }
  }

  public func retry(max: Int, strategy: RetryPolicy.Strategy = .immediate) -> Self {
    var copy = self
    copy.retryPolicy = RetryPolicy(maxAttempts: max, strategy: strategy)
    return copy
  }

  public func mock(with mock: MockResponse) -> Self {
    var copy = self
    copy.mock = mock
    return copy
  }

  public func mockIf(_ condition: Bool, with factory: () -> MockResponse) -> Self {
    guard condition else { return self }
    return self.mock(with: factory())
  }

  public func onAuthFailure(_ handler: @escaping (APIClient) async -> Void) -> Self {
    var copy = self
    copy.authFailureHandler = handler
    return copy
  }

  public func withMultipart(_ builder: @escaping (MultipartFormData) -> Void) -> Self {
    var copy = self
    copy.multipartFormDataBuilder = builder
    return copy
  }

  public func timeout(_ seconds: TimeInterval) -> Self {
    var copy = self
    copy.timeoutInterval = seconds
    return copy
  }

  public func intercept(_ block: @escaping (inout URLRequest) -> Void) -> Self {
    var copy = self
    copy.interceptor = block
    return copy
  }

  public func interceptResponse(_ block: @escaping (Data, HTTPURLResponse) throws -> Data) -> Self {
    var copy = self
    copy.responseInterceptor = block
    return copy
  }

  public func onError(_ handler: @escaping (Error) -> Void) -> Self {
    var copy = self
    copy.onErrorHandler = handler
    return copy
  }

  public func onProgress(_ handler: @escaping @Sendable (Progress) -> Void) -> Self {
    var copy = self
    copy.onProgress = handler
    return copy
  }

  public func delay(_ seconds: TimeInterval) -> Self {
    var copy = self
    copy.requestDelay = seconds
    return copy
  }
}
