import Foundation

public enum WebSocketEvent {
  case connected
  case disconnected
  case message(String)
  case data(Data)
  case error(Error)
}
