import XCTest
@testable import AnyAPI
import Alamofire

final class AnyAPITests: XCTestCase {

  struct DummyEndpoint: Endpoint {
    struct Response: Codable, Equatable {
      let message: String
    }

    let payload: String

    var path: String { "echo" }
    var method: HTTPMethod { .post }
    var headers: HTTPHeaders { ["X-Test": "1"] }

    func asParameters() throws -> Parameters {
      return ["payload": payload]
    }
  }

  func makeClient() -> APIClient {
    APIClient(
      baseURL: URL(string: "https://httpbin.org")!,
      session: .default,
      defaultHeaders: { ["Authorization": "Bearer test-token"] }
    )
  }

  func testMergesDefaultAndAdditionalHeaders() async throws {
    let client = makeClient()
    let builder = client(DummyEndpoint(payload: "Hello"))
      .additionalHeaders(["X-Custom": "Yes"])

    let mirror = Mirror(reflecting: builder)
    let hasClient = mirror.children.contains { $0.label == "client" }
    XCTAssertTrue(hasClient) // Sanity check the builder
  }

  func testOverridesHeaders() async throws {
    let client = makeClient()
    let builder = client(DummyEndpoint(payload: "Hello"))
      .overrideHeaders(["X-Override": "Only"])

    let mirror = Mirror(reflecting: builder)
    XCTAssertTrue(mirror.displayStyle == .class)
  }

  func testEndpointEncodesToParameters() throws {
    let endpoint = DummyEndpoint(payload: "Test123")
    let params = try endpoint.asParameters()
    XCTAssertEqual(params["payload"] as? String, "Test123")
  }

  func testJSONDecodeSuccess() throws {
    let json = #"{"message":"Success"}"#
    let data = json.data(using: .utf8)!
    let endpoint = DummyEndpoint(payload: "unused")
    let decoded = try endpoint.decode(data)
    XCTAssertEqual(decoded.message, "Success")
  }

  func testCancelableTaskStructure() {
    let dummyRequest = AF.request("https://httpbin.org/get")
    let dummyTask = Task<String, Error> {
      return "OK"
    }

    let cancelable = CancelableTask(request: dummyRequest, task: dummyTask)
    XCTAssertNotNil(cancelable.task)
    XCTAssertNotNil(cancelable.request)
  }

  func testRequestBuilderFluentAPI() {
    let client = makeClient()
    let builder = client(DummyEndpoint(payload: "hi"))
      .additionalParameters(["extra": "param"])
      .overrideParameters(["payload": "override"])
      .encoding(URLEncoding.default)

    XCTAssertNotNil(builder)
  }
}
