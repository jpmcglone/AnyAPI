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
