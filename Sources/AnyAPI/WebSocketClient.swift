import Foundation

@inline(__always)
public func onMain(_ body: @escaping () -> Void) {
  if Thread.isMainThread { body() }
  else { DispatchQueue.main.async(execute: body) }
}

public enum ConnectionPromotionMode {
  case firstValidMessage
  case ping
  case either
}

public enum WebSocketError: Error {
  case gaveUp
  case underlying(Error)
}

public enum WebSocketSendError: Error {
  case invalidUTF8
}

public enum ConnectionState: Equatable {
  case disconnected, disconnecting, connecting, connected, reconnecting, failed(String), gaveUp
}

@MainActor
public final class WebSocketClient: NSObject, URLSessionDelegate, ObservableObject {
  private let url: URL
  private var task: URLSessionWebSocketTask?
  private var session: URLSession!
  private let coding: APICodingConfig
  private var eventHandler: ((WebSocketEvent) -> Void)?
  private var pingTimer: Timer?
  private var intentionallyClosed = false

  var reconnectPolicy = ReconnectPolicy()
  public var promotionMode: ConnectionPromotionMode = .firstValidMessage
  public var giveUpOnInitialFailure: Bool = false
  public var ignoreMessageTypes: [String] = []

  private var isInitialConnect: Bool = true
  private var pendingReconnect: DispatchWorkItem?

  @Published public private(set) var connectionState: ConnectionState = .disconnected
  @Published public private(set) var lastMessage: String?
  @Published public private(set) var lastData: Data?
  @Published public private(set) var lastSentMessage: String?
  @Published public private(set) var lastSentData: Data?

  public var isConnected: Bool { connectionState == .connected }
  public var isConnecting: Bool { connectionState == .connecting }
  public var isReconnecting: Bool { connectionState == .reconnecting }

  private var waitingForFirstMessageTask: Task<Void, Never>?
  private var pingRetryTask: Task<Void, Never>?

  public init(
    url: URL,
    ignoreMessageTypes: [String] = [],
    coding: APICodingConfig = .default
  ) {
    self.url = url
    self.ignoreMessageTypes = ignoreMessageTypes
    self.coding = coding
    super.init()
    self.session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
  }

  public func connect() {
    // Bail if we’re already busy
    guard connectionState == .disconnected || connectionState.isFailure else {
      Logger.log("Connect skipped — current state: \(connectionState)", level: .warning, category: "WebSocket")
      return
    }

    Logger.log("Connecting to WebSocket...", level: .event, category: "WebSocket")

    intentionallyClosed = false
    session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    task    = session.webSocketTask(with: url)
    task?.resume()

    DispatchQueue.main.async {
      // snapshot *before* we mutate
      let wasFresh = (self.connectionState == .disconnected)

      self.connectionState = .connecting
      if wasFresh { self.reconnectPolicy.reset() }

      self.startWaitingForFirstMessage(timeout: 5)
      self.receive()

      if self.promotionMode == .ping || self.promotionMode == .either {
        self.waitForSuccessfulPing()
      }
    }
  }

  // MARK: – Ping-loop -----------------------------------------------------------
  private func waitForSuccessfulPing() {

    // stop any earlier ping-loop that might still be running
    pingRetryTask?.cancel()

    pingRetryTask = Task { [weak self] in
      guard let self else { return }

      do {
        try await self.waitUntilPingSuccess(timeout: 5)
        Logger.log("Ping confirmed connection within timeout.",
                   level: .success, category: "WebSocket")

        // ── ping worked → this IS a real connection ───────────────
        onMain {
          // 1️⃣ stop the “wait-for-first-message” timer
          self.cancelWaitingForFirstMessage()
          // 2️⃣ mark the connection as live (if it isn’t already)
          self.promoteConnectionIfNeeded()
        }

      } catch {
        // ---------- ping window elapsed without a single success ----------
        if self.isInitialConnect && self.giveUpOnInitialFailure {
          Logger.log("Initial ping failed. Giving up immediately.",
                     level: .error, category: "WebSocket")
          onMain {
            self.connectionState = .gaveUp
            self.handleEvent(.error(WebSocketError.gaveUp))
          }
        } else {
          Logger.log("Ping failed after timeout. Scheduling reconnect…",
                     level: .warning, category: "WebSocket")
          onMain {
            self.connectionState = .failed("Ping timeout")
            self.scheduleReconnect()
          }
        }
      }
    }
  }

  private func startWaitingForFirstMessage(timeout: TimeInterval) {
    waitingForFirstMessageTask?.cancel()
    waitingForFirstMessageTask = Task { [weak self] in
      guard let self else { return }

      Logger.log("Started waiting for real message (timeout in \(timeout)s)…",
                 level: .event, category: "WebSocket")

      try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
      if Task.isCancelled { return }

      if self.connectionState == .connecting {
        Logger.log("Timeout hit! No valid message received. Failing connection.",
                   level: .error, category: "WebSocket")
        onMain { self.failConnection(reason: "Timeout waiting for valid message") }
      }
    }
  }

  private func cancelWaitingForFirstMessage() {
    waitingForFirstMessageTask?.cancel()
    waitingForFirstMessageTask = nil
  }

  public func disconnect() {
    Logger.log("Disconnect requested.", level: .event, category: "WebSocket")

    // ▸ stop automatic reconnect if one is queued
    pendingReconnect?.cancel()
    pendingReconnect = nil
    reconnectPolicy.reset()

    intentionallyClosed = true
    stopPinging()

    connectionState = .disconnecting
    task?.cancel(with: .goingAway, reason: nil)
    task = nil

    session.invalidateAndCancel()
    session = nil

    // immediately tell the UI / caller
    connectionState = .disconnected
    handleEvent(.disconnected)

    Logger.log("Session invalidated after disconnect.", level: .event, category: "WebSocket")
  }

  public func onEvent(_ handler: @escaping (WebSocketEvent) -> Void) {
    self.eventHandler = handler
  }

  private func ping(completion: ((Error?) -> Void)? = nil) {
    Logger.log("Sending ping…", level: .event, category: "WebSocket")

    task?.sendPing { [weak self] error in
      guard let self else { return }

      if let error {
        Logger.log("Ping failed: \(error.localizedDescription)",
                   level: .error, category: "WebSocket")
        self.failConnection(reason: error.localizedDescription)
        completion?(error)
      } else {
        Logger.log("Ping succeeded.", level: .success, category: "WebSocket")
        self.promoteConnectionIfNeeded()
        completion?(nil)
      }
    }
  }

  private func waitUntilPingSuccess(timeout: TimeInterval = 5) async throws {
    Logger.log("Waiting for ping success with timeout \(timeout)s…",
               level: .event, category: "WebSocket")

    let start = Date()

    while Date().timeIntervalSince(start) < timeout {

      let ok = await withCheckedContinuation { cont in
        self.probePing { cont.resume(returning: $0) }
      }

      if ok {
        Logger.log("Ping confirmed connection within timeout.",
                   level: .success, category: "WebSocket")
        return
      }

      Logger.log("Probe-ping failed, retrying in 200 ms…",
                 level: .info, category: "WebSocket")
      try? await Task.sleep(nanoseconds: 200_000_000)
    }

    Logger.log("Ping timed out after \(timeout)s.",
               level: .error, category: "WebSocket")
    throw WebSocketError.gaveUp
  }

  public func send(_ text: String) {
    logSend(text)  // 🆕
    task?.send(.string(text)) { [weak self] error in
      guard let self = self else { return }
      if let error = error {
        Logger.log("Failed to send text: \(error.localizedDescription)", level: .error, category: "WebSocket")
        self.handleEvent(.error(error))
      } else {
        Logger.log("Sent text successfully.", level: .success, category: "WebSocket")
        DispatchQueue.main.async { self.lastSentMessage = text }
      }
    }
  }

  public func send(data: Data) {
    task?.send(.data(data)) { [weak self] error in
      guard let self = self else { return }
      if let error = error {
        Logger.log("Failed to send data: \(error.localizedDescription)", level: .error, category: "WebSocket")
        self.handleEvent(.error(error))
      } else {
        Logger.log("Sent data successfully.", level: .success, category: "WebSocket")
        DispatchQueue.main.async { self.lastSentData = data }
      }
    }
  }

  public func send<T: Encodable>(_ object: T) {
    do {
      let data = try coding.encoder.encode(object)
      if let jsonString = String(data: data, encoding: .utf8) {
        send(jsonString)
      } else {
        Logger.log("Encoding object to JSON string failed.", level: .error, category: "WebSocket")
        handleEvent(.error(WebSocketError.underlying(WebSocketSendError.invalidUTF8)))
      }
    } catch {
      Logger.log("Encoding object failed: \(error.localizedDescription)", level: .error, category: "WebSocket")
      handleEvent(.error(WebSocketError.underlying(error)))
    }
  }

  private func logSend(_ message: String) {
    print("""
    ========== [WebSocket SEND] ==========
    ➡️ Sent Message:
    \(message)
    ========== [End SEND] ==========
    """)
  }

  private func logReceive(_ message: String) {
    print("""
    ========== [WebSocket RECEIVE] ==========
    ⬅️ Received Message:
    \(message)
    ========== [End RECEIVE] ==========
    """)
  }

  private func logReceiveData(_ data: Data) {
    let snippet = String(data: data.prefix(500), encoding: .utf8) ?? "Non-UTF8 Data (\(data.count) bytes)"
    print("""
    ========== [WebSocket RECEIVE DATA] ==========
    ⬅️ Received Data (\(data.count) bytes):
    \(snippet)
    ========== [End RECEIVE DATA] ==========
    """)
  }

  private func receive() {
    Logger.log("Waiting to receive WebSocket message...", level: .event, category: "WebSocket")
    task?.receive { [weak self] result in
      guard let self else { return }

      switch result {
      case .success(let message):
        self.handleIncoming(message)
        self.receive()

      case .failure(let error):
        Logger.log("Receiving message failed: \(error.localizedDescription)", level: .error, category: "WebSocket")
        self.failConnection(reason: error.localizedDescription)
      }
    }
  }

  private func handleIncoming(_ message: URLSessionWebSocketTask.Message) {
    switch message {
    case .string(let text):
      logReceive(text)  // 🆕
      if shouldIgnoreMessage(text) {
        Logger.log("Ignored message due to type in ignore list.", level: .info, category: "WebSocket")
        cancelWaitingForFirstMessage()
        startWaitingForFirstMessage(timeout: 5)
        return
      }

      Logger.log("Received valid text message.", level: .success, category: "WebSocket")
      DispatchQueue.main.async { self.lastMessage = text }
      handleEvent(.message(text))

    case .data(let data):
      logReceiveData(data)  // 🆕
      Logger.log("Received valid binary data.", level: .success, category: "WebSocket")
      DispatchQueue.main.async { self.lastData = data }
      handleEvent(.data(data))

    @unknown default:
      Logger.log("Received unknown message type.", level: .warning, category: "WebSocket")
      return
    }

    cancelWaitingForFirstMessage()
    promoteConnectionIfNeeded()
  }

  private func promoteConnectionIfNeeded() {
    onMain {
      guard self.connectionState == .connecting || self.connectionState == .reconnecting else { return }

      Logger.log("Promoting connection to .connected.", level: .success, category: "WebSocket")
      self.connectionState  = .connected
      self.isInitialConnect = false
      self.reconnectPolicy.reset()

      self.handleEvent(.connected(reconnect: self.isReconnecting))
    }
  }

  private func failConnection(reason: String) {
    // if the caller already knows we're intentionally closed, just bail out
    if intentionallyClosed { return }

    onMain {
      if self.isInitialConnect && self.giveUpOnInitialFailure {
        Logger.log("Initial connect failed. Giving up immediately.", level: .error, category: "WebSocket")
        self.connectionState = .gaveUp
        self.handleEvent(.error(WebSocketError.gaveUp))
      } else {
        Logger.log("Connection failed. Scheduling reconnect...", level: .warning, category: "WebSocket")
        self.connectionState = .failed(reason)
        self.handleEvent(.error(WebSocketError.gaveUp))
        self.scheduleReconnect()
      }
    }
  }

  private func shouldIgnoreMessage(_ text: String) -> Bool {
    guard let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = json["type"] as? String else {
      return false
    }
    return ignoreMessageTypes.contains(type)
  }

  private func startPinging() {
    stopPinging()
    pingTimer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
      self?.ping()
    }
    RunLoop.main.add(pingTimer!, forMode: .common)
  }

  private func stopPinging() {
    pingTimer?.invalidate()
    pingTimer = nil
  }

  private func handleEvent(_ event: WebSocketEvent) {
    DispatchQueue.main.async {
      self.eventHandler?(event)
    }
  }

  // MARK: – Re-connect logic ----------------------------------------------------
  private func scheduleReconnect() {

    // stop any running ping-loop – no more pings while we’re offline
    pingRetryTask?.cancel()

    reconnectPolicy.backoff()

    guard reconnectPolicy.canRetry else {
      Logger.log("Max retries hit. Giving up.", level: .error, category: "WebSocket")
      stopPinging()                       // <- make sure the periodic ping timer stops
      onMain {
        self.connectionState = .gaveUp
        self.handleEvent(.error(WebSocketError.gaveUp))
      }
      return
    }

    Logger.log("Scheduling reconnect. Retry \(reconnectPolicy.retryCount)/\(reconnectPolicy.maxRetryCount). "
               + "Delay: \(reconnectPolicy.reconnectDelay)s",
               level: .warning, category: "WebSocket")

    // cancel any earlier one, then schedule a new work-item and keep a reference
    pendingReconnect?.cancel()
    let work = DispatchWorkItem { [weak self] in onMain { self?.connect() } }
    pendingReconnect = work
    DispatchQueue.main.asyncAfter(deadline: .now() + reconnectPolicy.reconnectDelay,
                                  execute: work)
  }

  private func probePing(completion: @escaping (Bool) -> Void) {
    task?.sendPing { error in
      if let err = error {
        Logger.log("Probe-ping failed: \(err.localizedDescription)",
                   level: .info, category: "WebSocket")
        completion(false)
      } else {
        Logger.log("Probe-ping succeeded.",
                   level: .debug, category: "WebSocket")
        completion(true)
      }
    }
  }
}

extension ConnectionState {
  var isFailure: Bool {
    if case .failed = self { return true }
    if case .gaveUp = self { return true }
    return false
  }
}
