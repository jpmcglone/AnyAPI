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
    // 🔥 pretty-print once, then re-throw a wrapped error
    print(pretty(description: error, in: data))
    throw AnyAPIError.decoding(error)
  }
}

enum AnyAPIError: LocalizedError {
  case unauthorized
  case decoding(Error)
  case server(String)          // generic
  case custom(String)          // user-supplied

  public var errorDescription: String? {
    switch self {
    case .unauthorized:
      return "You must be signed in to perform this action."
    case .server(let msg),
        .custom(let msg):
      return msg
    case .decoding(let error):
      return "Failed to decode: \(error)"
    }
  }
}

private func pretty(description error: DecodingError, in data: Data) -> String {
  func path(_ ctx: DecodingError.Context) -> String {
    ctx.codingPath.map(\.stringValue).joined(separator: " → ")
  }

  switch error {
  case .keyNotFound(let key, let ctx):
    return "❌ Missing key '\(key.stringValue)' at path «\(path(ctx))»."

  case .typeMismatch(let type, let ctx):
    return "❌ Type mismatch. Expected «\(type)» at path «\(path(ctx))». \(ctx.debugDescription)"

  case .valueNotFound(let type, let ctx):
    return "❌ Null/empty value for «\(type)» at path «\(path(ctx))»."

  case .dataCorrupted(let ctx):
    return "❌ Data corrupted at path «\(path(ctx))»: \(ctx.debugDescription)"
  @unknown default:
    return "❌ Unknown decoding error: \(error)"
  }

  let snippet = String(data: data.prefix(500), encoding: .utf8) ?? ""
  print("↳ JSON snippet:\n", snippet)
}
