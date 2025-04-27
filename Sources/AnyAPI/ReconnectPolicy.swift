import Foundation

struct ReconnectPolicy {
  var retryCount = 0
  var maxRetryCount: Int
  var reconnectDelay: TimeInterval
  let maxReconnectDelay: TimeInterval

  init(maxRetryCount: Int = 5, initialDelay: TimeInterval = 2, maxDelay: TimeInterval = 60) {
    self.maxRetryCount = maxRetryCount
    self.reconnectDelay = initialDelay
    self.maxReconnectDelay = maxDelay
  }

  mutating func reset() {
    retryCount = 0
    reconnectDelay = 2
  }

  mutating func backoff() {
    retryCount += 1
    reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)
  }

  var canRetry: Bool {
    retryCount < maxRetryCount
  }
}
