import Alamofire
import Foundation

public final class APIClient: ObservableObject {
  public let baseURL: URL
  public let session: Session
  private var defaultHeadersProvider: () -> HTTPHeaders

  @Published public private(set) var activeRequests: [TrackedRequest] = []

  public var requestCount: Int {
    activeRequests.count
  }

  public init(
    baseURL: URL,
    session: Session = .default,
    defaultHeaders: @escaping () -> HTTPHeaders
  ) {
    self.baseURL = baseURL
    self.session = session
    self.defaultHeadersProvider = defaultHeaders
  }

  public var defaultHeaders: HTTPHeaders {
    defaultHeadersProvider()
  }

  public func setDefaultHeaders(_ provider: @escaping () -> HTTPHeaders) {
    defaultHeadersProvider = provider
  }

  public func callAsFunction<E: Endpoint>(_ endpoint: E) -> RequestBuilder<E> {
    RequestBuilder(endpoint: endpoint, client: self)
  }

  public func execute<E: Endpoint>(_ endpoint: E, options: RequestOptions) async throws -> E.Response {
    if let mocked = try await handleMock(for: endpoint, with: options) {
      if let progressHandler = options.onProgress {
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 100
        progressHandler(progress)
      }
      return mocked
    }

    var tracked: TrackedRequest?

    // When tracking for a delay
    if let delay = options.requestDelay, delay > 0 {
      // Create a unique dummy request for delay tracking
      var req = URLRequest(url: baseURL.appendingPathComponent(endpoint.path))
      req.httpMethod = endpoint.method.rawValue
      req.addValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID") // ← ensures uniqueness
      tracked = await self.track(req)
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    do {
      let request = try self.buildRequest(for: endpoint, with: options)

      if let onProgress = options.onProgress {
        request.downloadProgress(closure: onProgress)
        request.uploadProgress(closure: onProgress)
      }

      let onRequest = options.onRequest

      if let urlRequest = request.convertible.urlRequest {
        if tracked == nil {
          tracked = await self.track(urlRequest)
        }
        onRequest?(urlRequest)
      }

      let startTime = Date()
      let response = await request.serializingData().response
      debugPrintResponse(response, startTime: startTime)

      // 🛠 Add this debug block:
      if let httpResponse = response.response {
        print("🌐 HTTP Status Code:", httpResponse.statusCode)
      }
      switch response.result {
      case .success(let data):
        print("📦 Raw Response Data Size:", data.count, "bytes")
        if let string = String(data: data, encoding: .utf8) {
          print("📜 Raw Response Body:", string)
        } else {
          print("📜 Raw Response Body: (non-UTF8 or empty)")
        }
      case .failure(let error):
        print("❌ Request failed:", error)
      }

      if let tracked = tracked {
        await self.untrack(tracked)
      }

      options.onResponse?(response)

      switch response.result {
      case .success(var data):
        if let httpResponse = response.response,
           let interceptor = options.responseInterceptor {
          data = try interceptor(data, httpResponse)
        }

        // 🆕 FIRST → check if 4xx/5xx and surface error immediately
        if let status = response.response?.statusCode,
           (400..<600).contains(status),
           !data.isEmpty,
           let body = String(data: data, encoding: .utf8) {
          throw AnyAPIError.server(body)
        }

        // 🆕 THEN check specifically 401
        if response.response?.statusCode == 401 {
          throw AnyAPIError.unauthorized
        }

        // 🧹 Finally decode only if status is OK
        let decoded = try decode(endpoint, options: options, data: data)
        return decoded

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
  
  public func batch<A: Endpoint, B: Endpoint>(_ a: A, _ b: B) async throws -> (A.Response, B.Response) {
    async let ra = execute(a, options: RequestOptions())
    async let rb = execute(b, options: RequestOptions())
    return try await (ra, rb)
  }

  public func batch<A: Endpoint, B: Endpoint, C: Endpoint>(_ a: A, _ b: B, _ c: C) async throws -> (A.Response, B.Response, C.Response) {
    async let ra = execute(a, options: RequestOptions())
    async let rb = execute(b, options: RequestOptions())
    async let rc = execute(c, options: RequestOptions())
    return try await (ra, rb, rc)
  }

  public func batch<E: Endpoint>(_ endpoints: [E]) async throws -> [E.Response] {
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
      let decoded = try decode(endpoint, options: options, data: data)
      return decoded

    case .failure(let error, let delay):
      if delay > 0 {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      }

      if let afError = error as? AFError,
         case .responseValidationFailed(let reason) = afError,
         case .unacceptableStatusCode(let code) = reason,
         code == 401,
         let handler = options.authFailureHandler {
        let weakSelf = self
        await handler(weakSelf)
        throw RetryableError.shouldRetry
      }

      throw error
    }
  }

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

  private func debugPrintResponse(_ response: AFDataResponse<Data>, startTime: Date) {
    var lines: [String] = []

    let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
    let elapsed = "\(elapsedMs)ms"

    if let request = response.request {
      lines.append("➡️ REQUEST [\(request.httpMethod ?? "UNKNOWN")] \(request.url?.absoluteString ?? "UNKNOWN URL")")
      if let headers = request.allHTTPHeaderFields {
        lines.append("Headers:")
        for (key, value) in headers {
          lines.append("  \(key): \(value)")
        }
      }
      if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
        lines.append("Body:")
        lines.append(bodyString)
      }
    } else {
      lines.append("⚠️ No request data available")
    }

    if let httpResponse = response.response {
      lines.append("⬅️ RESPONSE Status: \(httpResponse.statusCode) (\(elapsed))")
      for (key, value) in httpResponse.allHeaderFields {
        lines.append("  \(key): \(value)")
      }
    } else {
      lines.append("⚠️ No HTTP response")
    }

    if let data = response.data, !data.isEmpty {
      lines.append("📜 Body:")
      if let string = String(data: data, encoding: .utf8) {
        lines.append(string)
      } else {
        lines.append("(Non-UTF8 or binary data)")
      }
    } else {
      lines.append("📜 Empty response body.")
    }

    if let error = response.error {
      lines.append("❌ ERROR: \(error.localizedDescription)")
    }

    prettyPrint("API Call", lines)
  }

  private func track(_ request: URLRequest) async -> TrackedRequest {
    let tracked = TrackedRequest(request: request)
    await MainActor.run {
      self.activeRequests.append(tracked)
    }
    return tracked
  }

  private func untrack(_ tracked: TrackedRequest) async {
    await MainActor.run {
      self.activeRequests.removeAll { $0.id == tracked.id }
    }
  }

  private func prettyPrint(_ title: String, _ lines: [String]) {
    print("\n========== [\(title)] ==========")
    for line in lines {
      print(line)
    }
    print("========== [End \(title)] ==========\n")
  }
}

public enum RetryableError: Error {
  case shouldRetry
}

public struct TrackedRequest: Identifiable, Equatable {
  public let id = UUID()
  public let request: URLRequest

  public static func == (lhs: TrackedRequest, rhs: TrackedRequest) -> Bool {
    lhs.id == rhs.id
  }
}
