import Foundation

public enum WebSocketEvent {
  case connected(reconnect: Bool)
  case disconnected
  case message(String)
  case data(Data)
  case error(Error)
}

