import Foundation

public enum WebSocketError: Error {
  case gaveUp
  case underlying(Error)
}

public enum WebSocketSendError: Error {
  case invalidUTF8
}

public enum ConnectionState: Equatable {
  case disconnected
  case connecting
  case connected
  case reconnecting
  case failed(String)
  case gaveUp
}

public final class WebSocketClient: NSObject, URLSessionDelegate, ObservableObject {
  private let url: URL
  private var task: URLSessionWebSocketTask?
  private var session: URLSession!
  private var eventHandler: ((WebSocketEvent) -> Void)?

  var reconnectPolicy = ReconnectPolicy()

  private var pingTimer: Timer?

  private func startPinging() {
    stopPinging()
    pingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
      self?.ping()
    }
  }

  private func stopPinging() {
    pingTimer?.invalidate()
    pingTimer = nil
  }

  public func ping() {
    task?.sendPing { [weak self] error in
      if let error = error {
        self?.eventHandler?(.error(WebSocketError.underlying(error)))
        DispatchQueue.main.async {
          self?.connectionState = .failed(error.localizedDescription)
          self?.scheduleReconnect()
        }
      }
    }
  }

  public func waitUntilPingSuccess(timeout: TimeInterval = 5) async throws {
    guard let task = task else { throw WebSocketError.gaveUp }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      task.sendPing { error in
        if let error = error {
          continuation.resume(throwing: WebSocketError.underlying(error))
        } else {
          continuation.resume()
        }
      }
    }
  }

  @Published public private(set) var connectionState: ConnectionState = .disconnected

  public var isConnected: Bool {
    connectionState == .connected
  }

  public var isReconnecting: Bool {
    connectionState == .reconnecting
  }

  @Published public private(set) var lastMessage: String?
  @Published public private(set) var lastData: Data?

  public init(url: URL) {
    self.url = url
    super.init()
    self.session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
  }

  public func connect() {
    guard task == nil || task?.state != .running else { return }

    connectionState = .connecting
    task = session.webSocketTask(with: url)
    task?.resume()
    reconnectPolicy.reset()
    receive()
  }

  public func disconnect() {
    task?.cancel(with: .goingAway, reason: nil)
    task = nil
    connectionState = .disconnected
  }

  public func send(_ text: String) {
    task?.send(.string(text)) { [weak self] error in
      if let error = error {
        self?.eventHandler?(.error(error))
      }
    }
  }

  public func waitUntilConnected(timeout: TimeInterval = 10) async throws {
    let start = Date()
    while Date().timeIntervalSince(start) < timeout {
      if isConnected {
        return
      }
      try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    }
    throw WebSocketError.gaveUp
  }

  public func send<T: Encodable>(_ object: T) {
    do {
      let data = try JSONEncoder().encode(object)
      if let jsonString = String(data: data, encoding: .utf8) {
        send(jsonString)
      } else {
        eventHandler?(.error(WebSocketError.underlying(WebSocketSendError.invalidUTF8)))
      }
    } catch {
      eventHandler?(.error(WebSocketError.underlying(error)))
    }
  }

  public func send(data: Data) {
    task?.send(.data(data)) { [weak self] error in
      if let error = error {
        self?.eventHandler?(.error(error))
      }
    }
  }

  public func onEvent(_ handler: @escaping (WebSocketEvent) -> Void) {
    self.eventHandler = handler
  }

  private func receive() {
    task?.receive { [weak self] result in
      guard let self = self else { return }

      switch result {
      case .success(let message):
        if self.connectionState == .connecting || self.connectionState == .reconnecting {
          self.connectionState = .connected
        }
        switch message {
        case .string(let text):
          DispatchQueue.main.async { self.lastMessage = text }
          self.eventHandler?(.message(text))
        case .data(let data):
          DispatchQueue.main.async { self.lastData = data }
          self.eventHandler?(.data(data))
        @unknown default:
          break
        }
        self.receive() // Keep listening
      case .failure(let error):
        self.eventHandler?(.error(WebSocketError.underlying(error)))
        DispatchQueue.main.async {
          self.connectionState = .failed(error.localizedDescription)
          self.scheduleReconnect()
        }
      }
    }
  }

  public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    DispatchQueue.main.async {
      self.connectionState = .reconnecting
      self.scheduleReconnect()
    }
  }

  private func scheduleReconnect() {
    guard reconnectPolicy.canRetry else {
      connectionState = .gaveUp
      eventHandler?(.error(WebSocketError.gaveUp))
      return
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + reconnectPolicy.reconnectDelay) { [weak self] in
      guard let self = self else { return }
      if !self.isConnected {
        self.reconnectPolicy.backoff()
        self.connect()
      }
    }
  }
}
