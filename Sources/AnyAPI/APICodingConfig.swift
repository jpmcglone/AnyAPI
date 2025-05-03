import Foundation

public struct APICodingConfig {
  public static var `default`: APICodingConfig {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let string = try container.decode(String.self)

      if string == "0001-01-01T00:00:00Z" {
        return .distantPast // or just throw if you prefer
      }

      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

      guard let date = formatter.date(from: string) else {
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Expected ISO8601 with fractional seconds"
        )
      }

      return date
    }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.keyEncodingStrategy = .useDefaultKeys

    return APICodingConfig(encoder: encoder, decoder: decoder)
  }

  public let encoder: JSONEncoder
  public let decoder: JSONDecoder

  public init(
    encoder: JSONEncoder,
    decoder: JSONDecoder
  ) {
    self.encoder = encoder
    self.decoder = decoder
  }
}

public extension JSONDecoder {
  static var `default`: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.keyDecodingStrategy = .useDefaultKeys
    return decoder
  }
}

public extension JSONEncoder {
  static var `default`: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.keyEncodingStrategy = .useDefaultKeys
    return encoder
  }
}
