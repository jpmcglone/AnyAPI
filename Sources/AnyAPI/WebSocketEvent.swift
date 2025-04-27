import Foundation

public enum WebSocketEvent {
  case message(String)
  case data(Data)
  case error(Error)
}

