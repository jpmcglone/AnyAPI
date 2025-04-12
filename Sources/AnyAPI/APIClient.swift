import Alamofire
import Foundation

final class APIClient {
  let baseURL: URL
  let session: Session
  private let defaultHeadersProvider: () -> HTTPHeaders

  init(
    baseURL: URL,
    session: Session = .default,
    defaultHeaders: @escaping () -> HTTPHeaders
  ) {
    self.baseURL = baseURL
    self.session = session
    self.defaultHeadersProvider = defaultHeaders
  }

  var defaultHeaders: HTTPHeaders {
    defaultHeadersProvider()
  }

  func callAsFunction<E: Endpoint>(_ endpoint: E) -> RequestBuilder<E> {
    RequestBuilder(endpoint: endpoint, client: self)
  }

  fileprivate func execute<E: Endpoint>(_ endpoint: E, options: RequestOptions) async throws -> E.Response {
    if let mock = options.mock {
      switch mock {
      case .success(let data, let delay):
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        let decoded: Any = try options.decoder?(data) ?? endpoint.decode(data)
        return decoded as! E.Response

      case .failure(let error, let delay):
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        throw error
      }
    }

    let max = options.retryPolicy?.maxAttempts ?? 1
    for attempt in 1...max {
      do {
        let url = baseURL.appendingPathComponent(endpoint.path)
        let baseParams = try endpoint.asParameters()
        let finalParams = options.overrideParameters ?? baseParams.merging(options.additionalParameters) { _, new in new }
        let baseHeaders = defaultHeaders.merging(endpoint.headers)
        let finalHeaders = options.overrideHeaders ?? baseHeaders.merging(options.additionalHeaders)
        let encoding = options.encoding ?? (endpoint.method == .get ? URLEncoding.default : JSONEncoding.default)

        let request: DataRequest = {
          let timeout = options.timeoutInterval
          let interceptor = options.interceptor

          let modifier: @Sendable (inout URLRequest) -> Void = { req in
            if let timeout = timeout {
              req.timeoutInterval = timeout
            }
            interceptor?(&req)
          }

          if let multipartBuilder = options.multipartFormDataBuilder {
            return session.upload(
              multipartFormData: multipartBuilder,
              to: url,
              method: endpoint.method,
              headers: finalHeaders,
              requestModifier: modifier
            )
          } else {
            return session.request(
              url,
              method: endpoint.method,
              parameters: finalParams,
              encoding: encoding,
              headers: finalHeaders,
              requestModifier: modifier
            )
          }
        }()

        if let onProgress = options.onProgress {
          request.downloadProgress(closure: onProgress)
          request.uploadProgress(closure: onProgress)
        }

        let onRequest = options.onRequest
        let globalRequest = AnyAPI.logger.onRequest

        request.cURLDescription { _ in
          if let urlRequest = request.convertible.urlRequest {
            onRequest?(urlRequest)
            globalRequest?(urlRequest)
          }
        }

        let response = await request.serializingData().response
        options.onResponse?(response)
        AnyAPI.logger.onResponse?(response)

        switch response.result {
        case .success(var data):
          if let httpResponse = response.response,
             let interceptor = options.responseInterceptor {
            data = try interceptor(data, httpResponse)
          }
          let decoded: Any = try options.decoder?(data) ?? endpoint.decode(data)
          return decoded as! E.Response

        case .failure(let error):
          if let status = response.response?.statusCode, status == 401,
             let authHandler = options.authFailureHandler {
            await authHandler(self)
            continue
          }

          if attempt == max {
            options.onErrorHandler?(error)
            throw error
          } else {
            let delay = options.retryPolicy?.delay(for: attempt) ?? 0
            if delay > 0 {
              try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
          }
        }

      } catch {
        if attempt == max {
          options.onErrorHandler?(error)
          throw error
        } else {
          let delay = options.retryPolicy?.delay(for: attempt) ?? 0
          if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
          }
        }
      }
    }

    fatalError("Should never reach here — retry loop exit failed")
  }
}

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

    let task = Task<E.Response, Error> {
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
}

extension APIClient {
  func batch<A: Endpoint, B: Endpoint>(
    _ a: A,
    _ b: B
  ) async throws -> (A.Response, B.Response) {
    async let ra = execute(a, options: RequestOptions())
    async let rb = execute(b, options: RequestOptions())
    return try await (ra, rb)
  }

  func batch<A: Endpoint, B: Endpoint, C: Endpoint>(
    _ a: A,
    _ b: B,
    _ c: C
  ) async throws -> (A.Response, B.Response, C.Response) {
    async let ra = execute(a, options: RequestOptions())
    async let rb = execute(b, options: RequestOptions())
    async let rc = execute(c, options: RequestOptions())
    return try await (ra, rb, rc)
  }

  func batch<E: Endpoint>(_ endpoints: [E]) async throws -> [E.Response] {
    try await withThrowingTaskGroup(of: E.Response.self) { group in
      var results = [E.Response]()
      results.reserveCapacity(endpoints.count)

      for endpoint in endpoints {
        group.addTask {
          try await self.execute(endpoint, options: RequestOptions())
        }
      }

      for try await result in group {
        results.append(result)
      }

      return results
    }
  }
}
