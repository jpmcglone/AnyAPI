import Foundation

public final class WebSocketClient: NSObject, URLSessionDelegate {
  private let url: URL
  private var task: URLSessionWebSocketTask?
  private var session: URLSession!
  private var eventHandler: ((WebSocketEvent) -> Void)?

  public init(url: URL) {
    self.url = url
    super.init()
    self.session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
  }

  public func connect() {
    task = session.webSocketTask(with: url)
    task?.resume()
    receive()
    eventHandler?(.connected)
  }

  public func disconnect() {
    task?.cancel(with: .goingAway, reason: nil)
    eventHandler?(.disconnected)
  }

  public func send(_ text: String) {
    task?.send(.string(text)) { [weak self] error in
      if let error = error {
        self?.eventHandler?(.error(error))
      }
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
      switch result {
      case .success(let message):
        switch message {
        case .string(let text):
          self?.eventHandler?(.message(text))
        case .data(let data):
          self?.eventHandler?(.data(data))
        @unknown default:
          break
        }
        self?.receive() // Continue listening
      case .failure(let error):
        self?.eventHandler?(.error(error))
      }
    }
  }
}
