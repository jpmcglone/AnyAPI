import Foundation

enum MockResponse {
  case success(Data, delay: TimeInterval = 0)
  case failure(Error, delay: TimeInterval = 0)
}
