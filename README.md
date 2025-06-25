# AnyAPI

**AnyAPI** is a fluent, test-friendly, and extensible HTTP and WebSocket client built on top of [Alamofire](https://github.com/Alamofire/Alamofire). It's designed for power users who want full control without sacrificing readability.

---

## ✨ Features

- 🧱 Fluent builder pattern
- 🧪 Built-in mocking for tests (`mock`, `mockIf`)
- 💤 Optional artificial request delay (useful for testing loading states)
- 📊 Observable request tracking with `activeRequests` and `requestCount` for SwiftUI
- 🔁 Retry support with fixed or exponential strategies
- 🧼 Custom request/response interceptors
- 🧵 Manual timeout, header, parameter overrides
- 🧰 Multipart form uploads
- 🚦 Progress handlers
- 🔒 Auth failure handlers
- 🔄 Cancelable async tasks
- 🧪 `XCTest`-friendly
- 📡 WebSocket support (preview)
- 🧠 Designed for extensibility and readability

---

## 🧑‍💻 Basic Example

```swift
struct Login: Endpoint {
  struct Response: Decodable { let token: String }
  let username: String
  let password: String
  var path: String { "login" }
  var method: HTTPMethod { .post }
}

let client = APIClient(
  baseURL: URL(string: "https://api.example.com")!,
  defaultHeaders: { ["Authorization": "Bearer token"] }
)

let token = try await client(Login(username: "me", password: "pass"))
  .onRequest { print("➡️", $0) }
  .onResponse { print("⬅️", $0) }
  .decodeAs(Login.Response.self)
  .run
```

---

## 🧪 Mocking in Tests

```swift
let mockResponse = #"{"token":"abc123"}"#.data(using: .utf8)!

let token = try await client(Login(username: "me", password: "pass"))
  .mock(with: .success(mockResponse))
  .decodeAs(Login.Response.self)
  .run
```

Mock retry example:

```swift
var count = 0
let result = try await client(MyEndpoint())
  .mockIf(true) {
    count += 1
    if count == 1 {
      return .failure(URLError(.timedOut))
    } else {
      return .success(#"{"value":"ok"}"#.data(using: .utf8)!)
    }
  }
  .retry(max: 2)
  .decodeAs(MyEndpoint.Response.self)
  .run
```

---

## 🧩 Extensions

### Intercept Requests

```swift
.intercept { req in
  req.setValue("X-Test", forHTTPHeaderField: "Header")
}
```

### Intercept Responses

```swift
.interceptResponse { data, response in
  if response.statusCode == 204 {
    return "{}".data(using: .utf8)!
  }
  return data
}
```

### Auth Failure Handler

```swift
.onAuthFailure { client in
  try await refreshToken()
}
```

### ⏳ Add Delay (for testing)

```swift
.delay(1.5) // Adds 1.5 seconds before the request starts
```

---

## 🧼 SwiftUI Request Tracking

```swift
@StateObject var client = APIClient(...)
Text("Active Requests: \(client.requestCount)")
```

Or access `client.activeRequests` for more detail.

---

## 📡 WebSocket (Experimental)

```swift
let socket = WebSocketClient(url: URL(string: "wss://echo.websocket.org")!)
socket.onEvent { event in
  switch event {
  case .connected: print("Connected")
  case .message(let text): print("Received:", text)
  case .disconnected: print("Disconnected")
  case .error(let err): print("Error:", err)
  }
}
socket.connect()
socket.send("Hello world")
```

**New WebSocketClient Features:**
- Tracks `lastMessage`, `lastData`, **plus** `lastSentMessage` and `lastSentData`.
- Supports `waitUntilConnected(timeout:)` and `waitUntilPingSuccess(timeout:)`.
- Built-in reconnect strategy with exponential backoff.

---

## 📦 Installation

In Xcode:

```arduino
File > Add Packages...
```

Then paste the URL:

```arduino
https://github.com/your-org/AnyAPI.git
```

---

## 🧪 Run Tests

```bash
swift test
```

---

## 📄 License

MIT License. See LICENSE file.

---

🚀 **Happy shipping!**

## Enhanced Error Handling

AnyAPI now provides robust HTTP error handling with the `HTTPError` structure that captures response data even for non-200 status codes.

### Basic Error Handling

```swift
do {
    let response = try await client(endpoint).run
    // Handle successful response
} catch let httpError as HTTPError {
    print("HTTP Status: \(httpError.statusCode)")
    print("Response Body: \(httpError.responseBody ?? "No body")")
    
    // Extract error message from common JSON formats
    if let errorMessage = httpError.extractErrorMessage() {
        print("Error: \(errorMessage)")
    }
    
    // Check specific error types
    if httpError.isUnauthorized {
        // Handle 401 errors
    } else if httpError.isNotFound {
        // Handle 404 errors
    } else if httpError.isServerError {
        // Handle 5xx errors
    }
} catch {
    // Handle other errors (network failures, etc.)
    print("Network error: \(error)")
}
```

### Decoding Error Response Bodies

You can decode structured error responses:

```swift
struct APIErrorResponse: Codable {
    let error: String
    let code: Int
    let details: [String]?
}

do {
    let response = try await client(endpoint).run
} catch let httpError as HTTPError {
    do {
        let errorResponse = try httpError.decodeError(as: APIErrorResponse.self)
        print("API Error: \(errorResponse.error)")
        print("Error Code: \(errorResponse.code)")
    } catch {
        // Fallback to extracting simple error message
        let message = httpError.extractErrorMessage() ?? "Unknown error"
        print("Error: \(message)")
    }
}
```

### HTTPError Properties

The `HTTPError` struct provides comprehensive information about failed requests:

```swift
public struct HTTPError: Error {
    public let statusCode: Int              // HTTP status code
    public let data: Data?                  // Raw response body data
    public let response: HTTPURLResponse?   // Full HTTP response
    public let underlyingError: Error?      // Original error (if any)
    
    // Convenience properties
    public var isClientError: Bool          // 4xx errors
    public var isServerError: Bool          // 5xx errors  
    public var isUnauthorized: Bool         // 401 errors
    public var isForbidden: Bool            // 403 errors
    public var isNotFound: Bool             // 404 errors
    public var responseBody: String?        // Response as string
    
    // Utility methods
    public func extractErrorMessage() -> String?
    public func decodeError<T: Codable>(as type:) throws -> T
}
```

### Backward Compatibility

The original `AnyAPIError` enum is still available for backward compatibility and now includes bridging to `HTTPError`:

```swift
catch let error as AnyAPIError {
    switch error {
    case .http(let httpError):
        // New HTTPError wrapped in legacy enum
        print("HTTP Error: \(httpError.statusCode)")
    case .unauthorized:
        // Legacy unauthorized handling
    case .server(let message):
        // Legacy server error handling
    case .decoding(let decodingError):
        // Decoding error handling
    case .custom(let message):
        // Custom error handling
    }
}
```
