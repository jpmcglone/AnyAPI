import Foundation

struct ReconnectPolicy {
  private(set) var retryCount = 0
  let maxRetryCount: Int
  private(set) var reconnectDelay: TimeInterval
  let initialDelay: TimeInterval
  let maxReconnectDelay: TimeInterval

  init(maxRetryCount: Int = 5, initialDelay: TimeInterval = 2, maxDelay: TimeInterval = 60) {
    self.maxRetryCount = maxRetryCount
    self.initialDelay = initialDelay
    self.reconnectDelay = initialDelay
    self.maxReconnectDelay = maxDelay
  }

  mutating func reset() {
    retryCount = 0
    reconnectDelay = initialDelay
  }

  mutating func backoff() {
    retryCount += 1
    reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)
  }

  var canRetry: Bool {
    retryCount < maxRetryCount
  }
}
