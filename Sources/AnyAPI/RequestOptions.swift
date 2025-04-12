import Alamofire
import Foundation

struct RequestOptions {
  var additionalParameters: Parameters = [:]
  var additionalHeaders: HTTPHeaders = [:]
  var overrideParameters: Parameters? = nil
  var overrideHeaders: HTTPHeaders? = nil
  var encoding: ParameterEncoding? = nil
  var onRequest: ((URLRequest) -> Void)? = nil
  var onResponse: ((AFDataResponse<Data>) -> Void)? = nil
  var decoder: ((Data) throws -> Any)? = nil

  var mock: MockResponse? = nil
  var retryPolicy: RetryPolicy? = nil
  var authFailureHandler: ((APIClient) async -> Void)? = nil
  var multipartFormDataBuilder: ((MultipartFormData) -> Void)? = nil
  var timeoutInterval: TimeInterval? = nil
  var interceptor: ((inout URLRequest) -> Void)? = nil

  var responseInterceptor: ((Data, HTTPURLResponse) throws -> Data)? = nil
  var onErrorHandler: ((Error) -> Void)? = nil
  var onProgress: (@Sendable (Progress) -> Void)? = nil

  func additionalParameters(_ new: Parameters) -> Self {
    var copy = self
    copy.additionalParameters.merge(new) { _, new in new }
    return copy
  }

  func additionalHeaders(_ new: HTTPHeaders) -> Self {
    var copy = self
    copy.additionalHeaders.merge(new)
    return copy
  }

  func overrideParameters(_ new: Parameters) -> Self {
    var copy = self
    copy.overrideParameters = new
    return copy
  }

  func overrideHeaders(_ new: HTTPHeaders) -> Self {
    var copy = self
    copy.overrideHeaders = new
    return copy
  }

  func encoding(_ new: ParameterEncoding) -> Self {
    var copy = self
    copy.encoding = new
    return copy
  }

  func onRequest(_ callback: @escaping (URLRequest) -> Void) -> Self {
    var copy = self
    copy.onRequest = callback
    return copy
  }

  func onResponse(_ callback: @escaping (AFDataResponse<Data>) -> Void) -> Self {
    var copy = self
    copy.onResponse = callback
    return copy
  }

  func decodeWith(_ block: @escaping (Data) throws -> Any) -> Self {
    var copy = self
    copy.decoder = block
    return copy
  }

  func decodeAs<T: Decodable>(_ type: T.Type) -> Self {
    decodeWith { data in
      try JSONDecoder().decode(T.self, from: data)
    }
  }

  func decodeAs<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder) -> Self {
    decodeWith { data in
      try decoder.decode(T.self, from: data)
    }
  }

  func retry(max: Int, strategy: RetryPolicy.Strategy = .immediate) -> Self {
    var copy = self
    copy.retryPolicy = RetryPolicy(maxAttempts: max, strategy: strategy)
    return copy
  }

  func mock(with mock: MockResponse) -> Self {
    var copy = self
    copy.mock = mock
    return copy
  }

  func mockIf(_ condition: Bool, with factory: () -> MockResponse) -> Self {
    guard condition else { return self }
    return self.mock(with: factory())
  }

  func onAuthFailure(_ handler: @escaping (APIClient) async -> Void) -> Self {
    var copy = self
    copy.authFailureHandler = handler
    return copy
  }

  func withMultipart(_ builder: @escaping (MultipartFormData) -> Void) -> Self {
    var copy = self
    copy.multipartFormDataBuilder = builder
    return copy
  }

  func timeout(_ seconds: TimeInterval) -> Self {
    var copy = self
    copy.timeoutInterval = seconds
    return copy
  }

  func intercept(_ block: @escaping (inout URLRequest) -> Void) -> Self {
    var copy = self
    copy.interceptor = block
    return copy
  }

  func interceptResponse(_ block: @escaping (Data, HTTPURLResponse) throws -> Data) -> Self {
    var copy = self
    copy.responseInterceptor = block
    return copy
  }

  func onError(_ handler: @escaping (Error) -> Void) -> Self {
    var copy = self
    copy.onErrorHandler = handler
    return copy
  }

  func onProgress(_ handler: @escaping @Sendable (Progress) -> Void) -> Self {
    var copy = self
    copy.onProgress = handler
    return copy
  }
}


