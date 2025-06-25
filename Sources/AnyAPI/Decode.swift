import Foundation

func decode<E: Endpoint>(
  _ endpoint: E,
  options: RequestOptions,
  data: Data
) throws -> E.Response {

  do {
    // custom-decoder override first
    if let override = options.decoder {
      let any = try override(data)
      guard let typed = any as? E.Response else {
        throw DecodingError.typeMismatch(
          E.Response.self,
          .init(codingPath: [], debugDescription: "custom decoder returned \(type(of: any))")
        )
      }
      return typed
    }

    return try endpoint.decoder.decode(E.Response.self, from: data)

  } catch let error as DecodingError {
    print(pretty(description: error, in: data, decodingType: E.Response.self))
    throw HTTPError.decoding(error)
  }
}

// MARK: - Enhanced HTTP Error Structure

public struct HTTPError: Error {
  public let statusCode: Int
  public let data: Data?
  public let response: HTTPURLResponse?
  public let underlyingError: Error?
  
  public init(statusCode: Int, data: Data? = nil, response: HTTPURLResponse? = nil, underlyingError: Error? = nil) {
    self.statusCode = statusCode
    self.data = data
    self.response = response
    self.underlyingError = underlyingError
  }
  
  public var localizedDescription: String {
    if let underlyingError = underlyingError {
      return "HTTP \(statusCode): \(underlyingError.localizedDescription)"
    }
    return "HTTP \(statusCode)"
  }
  
  /// Decode the error response body as a specific type
  public func decodeError<T: Codable>(as type: T.Type, using decoder: JSONDecoder = JSONDecoder()) throws -> T {
    guard let data = data else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(codingPath: [], debugDescription: "No response data available")
      )
    }
    return try decoder.decode(type, from: data)
  }
  
  /// Extract a simple error message from common JSON error response formats
  public func extractErrorMessage() -> String? {
    guard let data = data else { return nil }
    
    // Try to parse as JSON and extract error message from common formats
    guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
      // If not JSON, return as string if possible
      return String(data: data, encoding: .utf8)
    }
    
    // Try common error message keys
    if let error = json["error"] as? String {
      return error
    }
    if let message = json["message"] as? String {
      return message
    }
    if let detail = json["detail"] as? String {
      return detail
    }
    if let description = json["description"] as? String {
      return description
    }
    
    // Try nested error objects
    if let errorObj = json["error"] as? [String: Any] {
      if let message = errorObj["message"] as? String {
        return message
      }
      if let description = errorObj["description"] as? String {
        return description
      }
    }
    
    // If no recognizable error format, return the raw JSON as string
    return String(data: data, encoding: .utf8)
  }
  
  /// Get the raw response body as a string
  public var responseBody: String? {
    guard let data = data else { return nil }
    return String(data: data, encoding: .utf8)
  }
  
  /// Check if this is a client error (4xx)
  public var isClientError: Bool {
    return (400..<500).contains(statusCode)
  }
  
  /// Check if this is a server error (5xx)
  public var isServerError: Bool {
    return (500..<600).contains(statusCode)
  }
  
  /// Check if this is an unauthorized error (401)
  public var isUnauthorized: Bool {
    return statusCode == 401
  }
  
  /// Check if this is a forbidden error (403)
  public var isForbidden: Bool {
    return statusCode == 403
  }
  
  /// Check if this is a not found error (404)
  public var isNotFound: Bool {
    return statusCode == 404
  }
}

// MARK: - Backward Compatibility

/// Legacy error enum for backward compatibility
public enum AnyAPIError: LocalizedError {
  case unauthorized
  case decoding(Error)
  case server(String)
  case custom(String)
  case http(HTTPError)  // Bridge to new HTTPError
  
  public var errorDescription: String? {
    switch self {
    case .unauthorized:
      return "You must be signed in to perform this action."
    case .server(let msg), .custom(let msg):
      return msg
    case .decoding(let error):
      return "Failed to decode: \(error)"
    case .http(let httpError):
      return httpError.localizedDescription
    }
  }
}

// MARK: - Convenience Extensions

extension HTTPError {
  /// Create HTTPError from network failure
  public static func networkFailure(_ error: Error) -> HTTPError {
    return HTTPError(statusCode: 0, underlyingError: error)
  }
  
  /// Create HTTPError for decoding failures
  public static func decoding(_ error: Error) -> HTTPError {
    return HTTPError(statusCode: 0, underlyingError: error)
  }
  
  /// Create HTTPError for unauthorized requests
  public static var unauthorized: HTTPError {
    return HTTPError(statusCode: 401)
  }
}

private func pretty<E>(
  description error: DecodingError,
  in data: Data,
  decodingType: E.Type
) -> String {
  func path(_ ctx: DecodingError.Context) -> String {
    ctx.codingPath.map(\.stringValue).joined(separator: " → ")
  }

  let baseMessage: String

  switch error {
  case .keyNotFound(let key, let ctx):
    baseMessage = "❌ Missing key '\(key.stringValue)' at path «\(path(ctx))» while decoding \(E.self)."
  case .typeMismatch(let type, let ctx):
    baseMessage = "❌ Type mismatch. Expected «\(type)» at path «\(path(ctx))» while decoding \(E.self). \(ctx.debugDescription)"
  case .valueNotFound(let type, let ctx):
    baseMessage = "❌ Null/empty value for «\(type)» at path «\(path(ctx))» while decoding \(E.self)."
  case .dataCorrupted(let ctx):
    baseMessage = "❌ Data corrupted at path «\(path(ctx))» while decoding \(E.self): \(ctx.debugDescription)"
  @unknown default:
    baseMessage = "❌ Unknown decoding error: \(error) while decoding \(E.self)."
  }

  let snippet = String(data: data.prefix(500), encoding: .utf8) ?? "n/a"
  return """
  \(baseMessage)
  ↳ JSON snippet:
  \(snippet)
  """
}
