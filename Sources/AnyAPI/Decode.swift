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
