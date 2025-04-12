import Alamofire
import Foundation

public protocol Endpoint: Encodable {
  associatedtype Response: Decodable

  var path: String { get }
  var method: HTTPMethod { get }
  var headers: HTTPHeaders { get }

  func decode(_ data: Data) throws -> Response
}

public extension Endpoint {
  var headers: HTTPHeaders { [:] }

  func decode(_ data: Data) throws -> Response {
    try JSONDecoder().decode(Response.self, from: data)
  }

  func asParameters() throws -> Parameters {
    let data = try JSONEncoder().encode(self)
    let json = try JSONSerialization.jsonObject(with: data, options: [])
    return json as? Parameters ?? [:]
  }
}
