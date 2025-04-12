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

  private func buildRequest<E: Endpoint>(
    for endpoint: E,
    with options: RequestOptions
  ) throws -> DataRequest {
    let url = baseURL.appendingPathComponent(endpoint.path)

    let baseParams = try endpoint.asParameters()
    let finalParams = options.overrideParameters ?? baseParams.merging(options.additionalParameters) { _, new in new }

    let baseHeaders = defaultHeaders.merging(endpoint.headers)
    let finalHeaders = options.overrideHeaders ?? baseHeaders.merging(options.additionalHeaders)

    let encoding = options.encoding ?? (endpoint.method == .get ? URLEncoding.default : JSONEncoding.default)

    let modifier: @Sendable (inout URLRequest) -> Void = { req in
      if let timeout = options.timeoutInterval {
        req.timeoutInterval = timeout
      }
      options.interceptor?(&req)
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
  }

  func execute<E: Endpoint>(_ endpoint: E, options: RequestOptions) async throws -> E.Response {
    if let mocked = try await handleMock(for: endpoint, with: options) {
      if let progressHandler = options.onProgress {
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 100
        progressHandler(progress)
      }
      return mocked
    }

    return try await withRetry(policy: options.retryPolicy) { attempt in
      let request = try self.buildRequest(for: endpoint, with: options)

      if let onProgress = options.onProgress {
        request.downloadProgress(closure: onProgress)
        request.uploadProgress(closure: onProgress)
      }

      let onRequest = options.onRequest

      request.cURLDescription { _ in
        if let urlRequest = request.convertible.urlRequest {
          onRequest?(urlRequest)
        }
      }

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
        if let status = response.response?.statusCode, status == 401,
           let authHandler = options.authFailureHandler {
          await authHandler(self)
          throw RetryableError.shouldRetry
        }

        options.onErrorHandler?(error)
        throw error
      }
    }
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

  private func handleMock<E: Endpoint>(
    for endpoint: E,
    with options: RequestOptions
  ) async throws -> E.Response? {
    guard let mock = options.mock else { return nil }

    var dummyRequest = URLRequest(url: baseURL.appendingPathComponent(endpoint.path))
    options.interceptor?(&dummyRequest)

    switch mock {
    case .success(let data, let delay):
      if delay > 0 {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      }
      let decoded: Any = try options.decoder?(data) ?? endpoint.decode(data)
      return decoded as? E.Response

    case .failure(let error, let delay):
      if delay > 0 {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      }

      // Simulate triggering the authFailureHandler manually when 401-like error
      if let afError = error as? AFError,
         case .responseValidationFailed(let reason) = afError,
         case .unacceptableStatusCode(let code) = reason,
         code == 401,
         let handler = options.authFailureHandler
      {
        await handler(self)
        throw RetryableError.shouldRetry
      }

      throw error
    }
  }
}

private extension APIClient {
  func withRetry<T>(
    policy: RetryPolicy?,
    operation: @escaping (_ attempt: Int) async throws -> T
  ) async throws -> T {
    let max = policy?.maxAttempts ?? 1

    for attempt in 1...max {
      do {
        return try await operation(attempt)
      } catch RetryableError.shouldRetry {
        let delay = policy?.delay(for: attempt) ?? 0
        if delay > 0 {
          try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
      } catch {
        if attempt == max {
          throw error
        } else {
          let delay = policy?.delay(for: attempt) ?? 0
          if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
          }
        }
      }
    }

    fatalError("withRetry should never reach here.")
  }
}

enum RetryableError: Error {
  case shouldRetry
}
