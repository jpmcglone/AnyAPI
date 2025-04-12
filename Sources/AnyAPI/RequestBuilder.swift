import Foundation

final class RequestBuilder<E: Endpoint> {
  private let endpoint: E
  private let client: APIClient
  private var options: RequestOptions

  init(endpoint: E, client: APIClient, options: RequestOptions = .init()) {
    self.endpoint = endpoint
    self.client = client
    self.options = options
  }

  func additionalParameters(_ p: Parameters) -> Self {
    options = options.additionalParameters(p)
    return self
  }

  func additionalHeaders(_ h: HTTPHeaders) -> Self {
    options = options.additionalHeaders(h)
    return self
  }

  func overrideParameters(_ p: Parameters) -> Self {
    options = options.overrideParameters(p)
    return self
  }

  func overrideHeaders(_ h: HTTPHeaders) -> Self {
    options = options.overrideHeaders(h)
    return self
  }

  func encoding(_ e: ParameterEncoding) -> Self {
    options = options.encoding(e)
    return self
  }

  func request(_ block: @escaping (URLRequest) -> Void) -> Self {
    options = options.onRequest(block)
    return self
  }

  func response(_ block: @escaping (AFDataResponse<Data>) -> Void) -> Self {
    options = options.onResponse(block)
    return self
  }

  func decodeWith(_ block: @escaping (Data) throws -> Any) -> Self {
    options = options.decodeWith(block)
    return self
  }

  var run: E.Response {
    get async throws {
      try await client.execute(endpoint, options: options)
    }
  }

  func start() throws -> CancelableTask<E.Response> {
    let url = client.baseURL.appendingPathComponent(endpoint.path)

    let baseParams = try endpoint.asParameters()
    let finalParams: Parameters = options.overrideParameters
    ?? baseParams.merging(options.additionalParameters) { _, new in new }

    let baseHeaders = client.defaultHeaders
      .merging(endpoint.headers)

    let finalHeaders: HTTPHeaders = options.overrideHeaders
    ?? baseHeaders.merging(options.additionalHeaders)

    let encoding = options.encoding ?? (endpoint.method == .get ? URLEncoding.default : JSONEncoding.default)

    let request = client.session.request(
      url,
      method: endpoint.method,
      parameters: finalParams,
      encoding: encoding,
      headers: finalHeaders
    )

    request.cURLDescription { _ in
      if let urlRequest = request.convertible.urlRequest {
        self.options.onRequest?(urlRequest)
      }
    }

    let task = Task<E.Response, Error> { [weak self] in
      guard let self else { throw URLError(.cancelled) }

      let response = await request.serializingData().response
      options.onResponse?(response)

      switch response.result {
      case .success(var data):
        if let httpResponse = response.response,
           let interceptor = options.responseInterceptor {
          data = try interceptor(data, httpResponse)
        }

        let decoded: Any = try options.decoder?(data) ?? endpoint.decode(data)
        return decoded as! E.Response
      case .failure(let error):
        throw error
      }
    }

    return CancelableTask(request: request, task: task)
  }

  func withMultipart() -> Self {
    options = options.withMultipart { form in
      if let parameters = try? self.endpoint.asParameters() {
        for (key, value) in parameters {
          if let str = value as? String {
            form.append(Data(str.utf8), withName: key)
          }
        }
      }
    }
    return self
  }

  func withMultipart(_ builder: @escaping (MultipartFormData) -> Void) -> Self {
    options = options.withMultipart(builder)
    return self
  }

  func mock(with mock: MockResponse) -> Self {
    options = options.mock(with: mock)
    return self
  }

  func mockIf(_ condition: Bool, with factory: () -> MockResponse) -> Self {
    options = options.mockIf(condition, with: factory)
    return self
  }

  func retry(max: Int, strategy: RetryPolicy.Strategy = .immediate) -> Self {
    options = options.retry(max: max, strategy: strategy)
    return self
  }

  func timeout(_ seconds: TimeInterval) -> Self {
    options = options.timeout(seconds)
    return self
  }

  func intercept(_ block: @escaping (inout URLRequest) -> Void) -> Self {
    options = options.intercept(block)
    return self
  }

  func interceptResponse(_ block: @escaping (Data, HTTPURLResponse) throws -> Data) -> Self {
    options = options.interceptResponse(block)
    return self
  }

  func onAuthFailure(_ handler: @escaping (APIClient) async -> Void) -> Self {
    options = options.onAuthFailure(handler)
    return self
  }

  func onError(_ handler: @escaping (Error) -> Void) -> Self {
    options = options.onError(handler)
    return self
  }

  func onProgress(_ handler: @escaping @Sendable (Progress) -> Void) -> Self {
    options = options.onProgress(handler)
    return self
  }

  func decodeAs<T: Decodable>(_ type: T.Type) -> Self {
    options = options.decodeAs(type)
    return self
  }

  func decodeAs<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder) -> Self {
    options = options.decodeAs(type, using: decoder)
    return self
  }
}
