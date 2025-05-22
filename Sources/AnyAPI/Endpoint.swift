import Alamofire
import Foundation

public protocol Endpoint: Encodable {
  associatedtype Response: Decodable

  var path: String { get }
  var method: HTTPMethod { get }
  var headers: HTTPHeaders { get }
  var decoder: JSONDecoder { get }

  func decode(_ data: Data) throws -> Response
  func asParameters() throws -> Parameters
}

public extension Endpoint {
  var method: HTTPMethod { .get }
  var headers: HTTPHeaders { [:] }
  var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .useDefaultKeys
    return decoder
  }

  func decode(_ data: Data) throws -> Response {
    try decoder.decode(Response.self, from: data)
  }

  func asParameters() throws -> Parameters {
    [:]
  }
}
