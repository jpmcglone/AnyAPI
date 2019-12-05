import ObjectMapper
import Alamofire
import AlamofireNetworkActivityIndicator
import AlamofireObjectMapper

public class AnyAPI {
  public var baseURL: URL?
  public var baseHeaders: HTTPHeaders?
  public var baseParameters: Parameters?
  public var activityIndicatorEnabled = false {
    didSet {
      NetworkActivityIndicatorManager.shared.isEnabled = activityIndicatorEnabled
    }
  }

  public init() {

  }

  @discardableResult
  public func request(method: HTTPMethod = .get, uri: String, parameters: [String: Any]? = nil) -> DataRequest {
    let urlString = "\(baseURL != nil ? "\(baseURL!.absoluteString)/" : "")\(uri)"

    // Full parameters
    var fullParameters = [String: Any]()
    if let baseParameters = baseParameters {
      for (key, value) in baseParameters {
        fullParameters[key] = value
      }
    }

    // Full baseHeaders
    var fullHeaders = [String: String]()
    if let baseHeaders = baseHeaders {
      for (key, value) in baseHeaders {
        fullHeaders[key] = value
      }
    }

    return Alamofire.request(
      urlString,
      method: method,
      parameters:
      fullParameters,
      encoding: URLEncoding.default,
      headers: fullHeaders
    )
  }
}
